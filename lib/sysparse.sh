#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/sysparse.sh - Structured Output Parsing (USOP)
# =============================================================================
# Description: Parse common Unix command output to structured JSON for AI agent
#              consumption. All parsers output USOP (Universal Structured Output
#              Protocol) JSON format.
# Purpose: Enables AI agents to consume system command output programmatically
#          without brittle text parsing.
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SYSPARSE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_SYSPARSE_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Source compat.sh for OS detection
# shellcheck source=compat.sh
source "${BASH_SOURCE%/*}/compat.sh" 2>/dev/null || {
    # Fallback: inline detection
    _compat_detect_os() {
        local uname_s
        uname_s="$(uname -s 2>/dev/null)" || uname_s="unknown"
        case "$uname_s" in
            Darwin) _COMPAT_OS="macos"; _COMPAT_OS_FAMILY="bsd" ;;
            Linux)  _COMPAT_OS="linux"; _COMPAT_OS_FAMILY="gnu" ;;
            FreeBSD|OpenBSD|NetBSD) _COMPAT_OS="${uname_s,,}"; _COMPAT_OS_FAMILY="bsd" ;;
            *) _COMPAT_OS="unknown"; _COMPAT_OS_FAMILY="unknown" ;;
        esac
    }
    compat::get_os_family() { _compat_detect_os; printf '%s' "$_COMPAT_OS_FAMILY"; }
    compat::get_os() { _compat_detect_os; printf '%s' "$_COMPAT_OS"; }
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Maximum items to return in output (prevents runaway output)
MAINFRAME_SYSPARSE_TRUNCATE="${MAINFRAME_SYSPARSE_TRUNCATE:-1000}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Escape string for JSON embedding
# Usage: _sysparse_escape_json "value"
_sysparse_escape_json() {
    local str="$1"
    local result=""
    local i char

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            '"')   result+='\"' ;;
            '\')   result+='\\' ;;
            $'\b') result+='\b' ;;
            $'\f') result+='\f' ;;
            $'\n') result+='\n' ;;
            $'\r') result+='\r' ;;
            $'\t') result+='\t' ;;
            *)
                # Escape control characters as \uXXXX
                if [[ "$char" < $'\x20' ]]; then
                    printf -v char '\\u%04x' "'$char"
                fi
                result+="$char"
                ;;
        esac
    done

    printf '%s' "$result"
}

# Emit USOP error JSON to stderr
# Usage: _sysparse_error "code" "message" ["details"]
_sysparse_error() {
    local code="$1"
    local message="$2"
    local details="${3:-}"
    local escaped_msg escaped_details

    escaped_msg=$(_sysparse_escape_json "$message")
    escaped_details=$(_sysparse_escape_json "$details")

    if [[ -n "$details" ]]; then
        printf '{"error":{"code":"%s","message":"%s","details":"%s"}}\n' \
            "$code" "$escaped_msg" "$escaped_details" >&2
    else
        printf '{"error":{"code":"%s","message":"%s"}}\n' \
            "$code" "$escaped_msg" >&2
    fi
}

# Join array elements with comma
# Usage: _sysparse_join_array "${array[@]}"
_sysparse_join_array() {
    local first=true
    printf '['
    for item in "$@"; do
        $first || printf ','
        first=false
        printf '%s' "$item"
    done
    printf ']'
}

# Validate we have a required command
# Usage: _sysparse_require_cmd "command"
_sysparse_require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        _sysparse_error "E_CMD_NOT_FOUND" "Required command not found: $cmd"
        return 1
    fi
    return 0
}

# =============================================================================
# parse_ps - Parse process list to JSON
# =============================================================================
# @description Parse ps command output to JSON
# @pre        None (runs ps internally)
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array (default)
# @param      --pid - Filter by PID
# @param      --user - Filter by user
# @param      --name - Filter by process name pattern
# @param      --format - ps output format (default: aux)
# @stdout     JSON array of process objects
# @return     0 on success
#
# Output: [{"pid":N,"user":"...","cpu":N.N,"mem":N.N,"command":"...","started":"..."}]
#
# Usage: parse_ps --json
# Usage: parse_ps --user root --json
# Usage: parse_ps --name nginx
# =============================================================================
parse_ps() {
    local filter_user="" filter_name="" filter_pid=""
    local ps_format="aux"
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user)
                filter_user="$2"
                shift 2
                ;;
            --name)
                filter_name="$2"
                shift 2
                ;;
            --pid)
                filter_pid="$2"
                shift 2
                ;;
            --format)
                ps_format="$2"
                shift 2
                ;;
            --json)
                # Always JSON output
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate PID if provided
    if [[ -n "$filter_pid" ]] && [[ ! "$filter_pid" =~ ^[0-9]+$ ]]; then
        _sysparse_error "E_INVALID_PID" "PID must be a number" "$filter_pid"
        return 1
    fi

    # Run ps based on format
    local ps_output
    case "$ps_format" in
        aux)
            ps_output=$(ps aux 2>/dev/null) || {
                _sysparse_error "E_PS_FAILED" "Failed to execute ps aux"
                return 1
            }
            ;;
        -ef)
            ps_output=$(ps -ef 2>/dev/null) || {
                _sysparse_error "E_PS_FAILED" "Failed to execute ps -ef"
                return 1
            }
            ;;
        *)
            ps_output=$(ps "$ps_format" 2>/dev/null) || {
                _sysparse_error "E_PS_FAILED" "Failed to execute ps $ps_format"
                return 1
            }
            ;;
    esac

    # Parse ps aux output: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    while IFS= read -r line; do
        # Skip header line
        [[ "$line" =~ ^USER[[:space:]] ]] && continue
        [[ "$line" =~ ^UID[[:space:]] ]] && continue
        [[ -z "$line" ]] && continue

        # Enforce truncation limit
        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        local user pid cpu mem vsz rss tty stat start time cmd
        # shellcheck disable=SC2034
        read -r user pid cpu mem vsz rss tty stat start time cmd <<< "$line"

        # Command is everything after time field - handle spaces
        local rest="${line#*"$time "}"
        [[ -n "$rest" ]] && cmd="$rest"

        # Apply filters
        [[ -n "$filter_user" && "$user" != "$filter_user" ]] && continue
        [[ -n "$filter_pid" && "$pid" != "$filter_pid" ]] && continue
        if [[ -n "$filter_name" ]]; then
            [[ ! "$cmd" =~ $filter_name ]] && continue
        fi

        # Escape values
        local escaped_user escaped_cmd escaped_tty escaped_stat escaped_start escaped_time
        escaped_user=$(_sysparse_escape_json "$user")
        escaped_cmd=$(_sysparse_escape_json "$cmd")
        escaped_tty=$(_sysparse_escape_json "$tty")
        escaped_stat=$(_sysparse_escape_json "$stat")
        escaped_start=$(_sysparse_escape_json "$start")
        escaped_time=$(_sysparse_escape_json "$time")

        # Validate numeric fields
        [[ ! "$cpu" =~ ^[0-9.]+$ ]] && cpu="0"
        [[ ! "$mem" =~ ^[0-9.]+$ ]] && mem="0"

        results+=("{\"pid\":$pid,\"user\":\"$escaped_user\",\"cpu\":$cpu,\"mem\":$mem,\"vsz\":${vsz:-0},\"rss\":${rss:-0},\"tty\":\"$escaped_tty\",\"stat\":\"$escaped_stat\",\"started\":\"$escaped_start\",\"time\":\"$escaped_time\",\"command\":\"$escaped_cmd\"}")
        ((count++))
    done <<< "$ps_output"

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_df - Parse disk usage to JSON
# =============================================================================
# @description Parse df (disk free) output to JSON
# @pre        None
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array
# @param      --human - Include human-readable sizes
# @param      --type - Filter by filesystem type
# @stdout     JSON array of filesystem objects
# @return     0 on success
#
# Output: [{"filesystem":"...","type":"...","size_bytes":N,"used_bytes":N,"available_bytes":N,
#          "use_percent":N,"mount":"..."}]
#
# Usage: parse_df --json
# Usage: parse_df --type ext4 --json
# =============================================================================
parse_df() {
    local filter_type="" include_human=0
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                filter_type="$2"
                shift 2
                ;;
            --human)
                include_human=1
                shift
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Get df output with byte sizes
    local df_output
    if [[ "$(compat::get_os_family)" == "bsd" ]]; then
        # BSD/macOS: Use -P for POSIX output and -k for kilobytes
        df_output=$(df -Pk 2>/dev/null) || {
            _sysparse_error "E_DF_FAILED" "Failed to execute df"
            return 1
        }
    else
        # GNU: Use -B1 for exact bytes
        df_output=$(df -P 2>/dev/null) || {
            _sysparse_error "E_DF_FAILED" "Failed to execute df"
            return 1
        }
    fi

    # Parse df output: Filesystem 1K-blocks Used Available Use% Mounted on
    while IFS= read -r line; do
        # Skip header
        [[ "$line" =~ ^Filesystem ]] && continue
        [[ -z "$line" ]] && continue

        # Enforce truncation limit
        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        local fs blocks used avail percent mount
        if [[ "$line" =~ ^(.*[^[:space:]])[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+%)[[:space:]]+(.+)$ ]]; then
            fs="${BASH_REMATCH[1]}"
            blocks="${BASH_REMATCH[2]}"
            used="${BASH_REMATCH[3]}"
            avail="${BASH_REMATCH[4]}"
            percent="${BASH_REMATCH[5]}"
            mount="${BASH_REMATCH[6]}"
        else
            continue
        fi

        # Remove % from percent
        percent="${percent%\%}"
        [[ ! "$percent" =~ ^[0-9]+$ ]] && percent="0"

        # Convert 1K blocks to bytes (if not already bytes)
        local size_bytes used_bytes avail_bytes
        if [[ "$(compat::get_os_family)" == "bsd" ]]; then
            size_bytes=$((blocks * 1024))
            used_bytes=$((used * 1024))
            avail_bytes=$((avail * 1024))
        else
            # Assume already 1K blocks for POSIX mode
            size_bytes=$((blocks * 1024))
            used_bytes=$((used * 1024))
            avail_bytes=$((avail * 1024))
        fi

        # Get filesystem type
        local fstype=""
        if [[ "$(compat::get_os_family)" == "bsd" ]]; then
            # macOS: Get type from mount output
            fstype=$(mount 2>/dev/null | awk -v mp="$mount" 'index($0, " on " mp " (") { line=$0; sub(/^.*\(/, "", line); sub(/,.*/, "", line); print line; exit }')
        else
            # Linux: Use df -T or stat -f
            fstype=$(df -T "$mount" 2>/dev/null | tail -1 | awk '{print $2}')
        fi
        [[ -z "$fstype" ]] && fstype="unknown"

        # Apply type filter
        [[ -n "$filter_type" && "$fstype" != "$filter_type" ]] && continue

        # Escape values
        local escaped_fs escaped_mount escaped_type
        escaped_fs=$(_sysparse_escape_json "$fs")
        escaped_mount=$(_sysparse_escape_json "$mount")
        escaped_type=$(_sysparse_escape_json "$fstype")

        local entry="{\"filesystem\":\"$escaped_fs\",\"type\":\"$escaped_type\",\"size_bytes\":$size_bytes,\"used_bytes\":$used_bytes,\"available_bytes\":$avail_bytes,\"use_percent\":$percent,\"mount\":\"$escaped_mount\""

        if (( include_human )); then
            # Add human-readable sizes
            local size_hr used_hr avail_hr
            size_hr=$(_sysparse_format_bytes "$size_bytes")
            used_hr=$(_sysparse_format_bytes "$used_bytes")
            avail_hr=$(_sysparse_format_bytes "$avail_bytes")
            entry+=",\"size_human\":\"$size_hr\",\"used_human\":\"$used_hr\",\"available_human\":\"$avail_hr\""
        fi

        entry+="}"
        results+=("$entry")
        ((count++))
    done <<< "$df_output"

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# Helper: Format bytes to human-readable
_sysparse_format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local value="$bytes"

    while (( value >= 1024 && unit_index < 5 )); do
        value=$((value / 1024))
        ((unit_index++))
    done

    printf '%d%s' "$value" "${units[$unit_index]}"
}

# =============================================================================
# parse_ls - Parse file listing to JSON
# =============================================================================
# @description Parse ls command output to JSON
# @pre        Directory/file exists
# @post       None (read-only)
# @idempotent Yes
# @param      $1 path - Directory or file path
# @param      --json - Output as JSON array
# @param      --all - Include hidden files
# @param      --recursive - Recurse into directories
# @param      --type - Filter: file|dir|link|all
# @stdout     JSON array of file objects
# @return     0 on success, 1 if path not found
#
# Output: [{"name":"...","type":"file|dir|link","size":N,"perms":"...","owner":"...","modified":"ISO8601"}]
#
# Usage: parse_ls "/tmp" --json
# Usage: parse_ls "." --all --type file --json
# =============================================================================
parse_ls() {
    local path="${1:-.}"
    shift || true

    local show_all=0 recursive=0 filter_type="all"
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                show_all=1
                shift
                ;;
            --recursive|-R)
                recursive=1
                shift
                ;;
            --type)
                filter_type="$2"
                shift 2
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate path exists
    if [[ ! -e "$path" ]]; then
        _sysparse_error "E_PATH_NOT_FOUND" "Path does not exist" "$path"
        return 1
    fi

    # Validate filter_type
    case "$filter_type" in
        file|dir|link|all) ;;
        *)
            _sysparse_error "E_INVALID_TYPE" "Invalid type filter" "$filter_type"
            return 1
            ;;
    esac

    # Use find instead of ls for safer parsing
    local find_opts=()
    find_opts+=("$path")

    if (( ! recursive )); then
        find_opts+=("-maxdepth" "1")
    fi

    if (( ! show_all )); then
        # Exclude hidden files
        find_opts+=("!" "-name" ".*")
    fi

    # Apply type filter
    case "$filter_type" in
        file) find_opts+=("-type" "f") ;;
        dir)  find_opts+=("-type" "d") ;;
        link) find_opts+=("-type" "l") ;;
    esac

    find_opts+=("-print0")

    # Process files
    while IFS= read -r -d '' file; do
        # Skip the base directory itself if not recursive
        [[ "$file" == "$path" ]] && continue

        # Enforce truncation limit
        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        # Get file info
        local name ftype size perms owner group mtime_epoch
        name=$(basename "$file")

        # Determine type
        if [[ -L "$file" ]]; then
            ftype="link"
        elif [[ -d "$file" ]]; then
            ftype="dir"
        elif [[ -f "$file" ]]; then
            ftype="file"
        else
            ftype="other"
        fi

        # Get stats - handle BSD vs GNU differences
        if [[ "$(compat::get_os_family)" == "bsd" ]]; then
            size=$(stat -f '%z' "$file" 2>/dev/null || echo 0)
            perms=$(stat -f '%Sp' "$file" 2>/dev/null || echo "----------")
            owner=$(stat -f '%Su' "$file" 2>/dev/null || echo "unknown")
            group=$(stat -f '%Sg' "$file" 2>/dev/null || echo "unknown")
            mtime_epoch=$(stat -f '%m' "$file" 2>/dev/null || echo 0)
        else
            size=$(stat -c '%s' "$file" 2>/dev/null || echo 0)
            perms=$(stat -c '%A' "$file" 2>/dev/null || echo "----------")
            owner=$(stat -c '%U' "$file" 2>/dev/null || echo "unknown")
            group=$(stat -c '%G' "$file" 2>/dev/null || echo "unknown")
            mtime_epoch=$(stat -c '%Y' "$file" 2>/dev/null || echo 0)
        fi

        # Convert mtime to ISO8601
        local mtime_iso
        if [[ "$(compat::get_os_family)" == "bsd" ]]; then
            mtime_iso=$(date -r "$mtime_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "unknown")
        else
            mtime_iso=$(date -d "@$mtime_epoch" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "unknown")
        fi

        # Get link target if symlink
        local link_target=""
        if [[ "$ftype" == "link" ]]; then
            link_target=$(readlink "$file" 2>/dev/null || echo "")
        fi

        # Escape values
        local escaped_name escaped_perms escaped_owner escaped_group escaped_mtime escaped_target
        escaped_name=$(_sysparse_escape_json "$name")
        escaped_perms=$(_sysparse_escape_json "$perms")
        escaped_owner=$(_sysparse_escape_json "$owner")
        escaped_group=$(_sysparse_escape_json "$group")
        escaped_mtime=$(_sysparse_escape_json "$mtime_iso")
        escaped_target=$(_sysparse_escape_json "$link_target")

        local entry="{\"name\":\"$escaped_name\",\"type\":\"$ftype\",\"size\":$size,\"perms\":\"$escaped_perms\",\"owner\":\"$escaped_owner\",\"group\":\"$escaped_group\",\"modified\":\"$escaped_mtime\""

        if [[ -n "$link_target" ]]; then
            entry+=",\"target\":\"$escaped_target\""
        fi

        entry+="}"
        results+=("$entry")
        ((count++))
    done < <(find "${find_opts[@]}" 2>/dev/null)

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_netstat - Parse network connections to JSON
# =============================================================================
# @description Parse netstat/ss output to JSON
# @pre        netstat or ss command available
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array
# @param      --listening - Only listening sockets
# @param      --tcp - Only TCP
# @param      --udp - Only UDP
# @param      --port - Filter by port number
# @stdout     JSON array of connection objects
# @return     0 on success
#
# Output: [{"proto":"tcp|udp","local_addr":"...","local_port":N,"remote_addr":"...","remote_port":N,
#          "state":"LISTEN|ESTABLISHED|...","pid":N,"process":"..."}]
#
# Usage: parse_netstat --json --listening
# Usage: parse_netstat --tcp --port 80 --json
# =============================================================================
parse_netstat() {
    local listening_only=0 tcp_only=0 udp_only=0 filter_port=""
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --listening|-l)
                listening_only=1
                shift
                ;;
            --tcp|-t)
                tcp_only=1
                shift
                ;;
            --udp|-u)
                udp_only=1
                shift
                ;;
            --port|-p)
                filter_port="$2"
                shift 2
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate port if provided
    if [[ -n "$filter_port" ]] && [[ ! "$filter_port" =~ ^[0-9]+$ ]]; then
        _sysparse_error "E_INVALID_PORT" "Port must be a number" "$filter_port"
        return 1
    fi

    # Prefer ss over netstat on Linux
    local use_ss=0
    if command -v ss &>/dev/null && [[ "$(compat::get_os_family)" == "gnu" ]]; then
        use_ss=1
    fi

    local net_output
    if (( use_ss )); then
        # Build ss command
        local ss_opts="-n"
        (( listening_only )) && ss_opts+="l"
        (( tcp_only )) && ss_opts+="t"
        (( udp_only )) && ss_opts+="u"
        [[ "$tcp_only" -eq 0 && "$udp_only" -eq 0 ]] && ss_opts+="tu"
        ss_opts+="p"

        net_output=$(ss "$ss_opts" 2>/dev/null) || {
            _sysparse_error "E_SS_FAILED" "Failed to execute ss"
            return 1
        }

        # Parse ss output
        while IFS= read -r line; do
            # Skip header
            [[ "$line" =~ ^Netid ]] && continue
            [[ "$line" =~ ^State ]] && continue
            [[ -z "$line" ]] && continue

            if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
                break
            fi

            # ss format: Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
            # or: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
            local proto state recvq sendq local_addr peer_addr process_info
            if [[ "$line" =~ ^(tcp|udp) ]]; then
                read -r proto state recvq sendq local_addr peer_addr process_info <<< "$line"
            else
                read -r state recvq sendq local_addr peer_addr process_info <<< "$line"
                proto="tcp"  # Default
            fi

            # Parse local address and port
            local laddr lport
            if [[ "$local_addr" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
                # IPv6
                laddr="${BASH_REMATCH[1]}"
                lport="${BASH_REMATCH[2]}"
            elif [[ "$local_addr" =~ ^(.+):([0-9*]+)$ ]]; then
                laddr="${BASH_REMATCH[1]}"
                lport="${BASH_REMATCH[2]}"
            else
                laddr="$local_addr"
                lport="0"
            fi
            [[ "$lport" == "*" ]] && lport="0"

            # Parse peer address and port
            local raddr rport
            if [[ "$peer_addr" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
                raddr="${BASH_REMATCH[1]}"
                rport="${BASH_REMATCH[2]}"
            elif [[ "$peer_addr" =~ ^(.+):([0-9*]+)$ ]]; then
                raddr="${BASH_REMATCH[1]}"
                rport="${BASH_REMATCH[2]}"
            else
                raddr="$peer_addr"
                rport="0"
            fi
            [[ "$rport" == "*" ]] && rport="0"

            # Apply port filter
            if [[ -n "$filter_port" ]]; then
                [[ "$lport" != "$filter_port" && "$rport" != "$filter_port" ]] && continue
            fi

            # Parse process info: users:(("process",pid=123,fd=4))
            local pid=0 pname=""
            if [[ "$process_info" =~ pid=([0-9]+) ]]; then
                pid="${BASH_REMATCH[1]}"
            fi
            if [[ "$process_info" =~ \(\(\"([^\"]+)\" ]]; then
                pname="${BASH_REMATCH[1]}"
            fi

            # Escape values
            local escaped_laddr escaped_raddr escaped_state escaped_pname
            escaped_laddr=$(_sysparse_escape_json "$laddr")
            escaped_raddr=$(_sysparse_escape_json "$raddr")
            escaped_state=$(_sysparse_escape_json "$state")
            escaped_pname=$(_sysparse_escape_json "$pname")

            results+=("{\"proto\":\"$proto\",\"local_addr\":\"$escaped_laddr\",\"local_port\":$lport,\"remote_addr\":\"$escaped_raddr\",\"remote_port\":$rport,\"state\":\"$escaped_state\",\"pid\":$pid,\"process\":\"$escaped_pname\"}")
            ((count++))
        done <<< "$net_output"
    else
        # Use netstat
        local netstat_opts="-n"
        if [[ "$(compat::get_os_family)" == "bsd" ]]; then
            # BSD netstat
            (( listening_only )) && netstat_opts+="a"
            (( tcp_only )) && netstat_opts+=" -p tcp"
            (( udp_only )) && netstat_opts+=" -p udp"
        else
            # GNU netstat
            (( listening_only )) && netstat_opts+="l"
            (( tcp_only )) && netstat_opts+="t"
            (( udp_only )) && netstat_opts+="u"
            [[ "$tcp_only" -eq 0 && "$udp_only" -eq 0 ]] && netstat_opts+="tu"
            netstat_opts+="p"
        fi

        # shellcheck disable=SC2086
        net_output=$(netstat $netstat_opts 2>/dev/null) || {
            _sysparse_error "E_NETSTAT_FAILED" "Failed to execute netstat"
            return 1
        }

        while IFS= read -r line; do
            # Skip headers and empty lines
            [[ "$line" =~ ^Active ]] && continue
            [[ "$line" =~ ^Proto ]] && continue
            [[ -z "$line" ]] && continue

            if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
                break
            fi

            # Parse netstat output (format varies by OS)
            local proto local_addr remote_addr state pid_prog
            # Linux: Proto Recv-Q Send-Q Local Address Foreign Address State PID/Program
            # BSD: Proto Recv-Q Send-Q Local Address Foreign Address (state)

            read -r proto _ _ local_addr remote_addr state pid_prog <<< "$line"

            # Normalize proto
            proto="${proto,,}"
            [[ "$proto" =~ ^tcp ]] && proto="tcp"
            [[ "$proto" =~ ^udp ]] && proto="udp"

            # Parse addresses
            local laddr lport raddr rport
            if [[ "$local_addr" =~ ^(.+)[.:]([0-9*]+)$ ]]; then
                laddr="${BASH_REMATCH[1]}"
                lport="${BASH_REMATCH[2]}"
            else
                laddr="$local_addr"
                lport="0"
            fi
            [[ "$lport" == "*" ]] && lport="0"

            if [[ "$remote_addr" =~ ^(.+)[.:]([0-9*]+)$ ]]; then
                raddr="${BASH_REMATCH[1]}"
                rport="${BASH_REMATCH[2]}"
            else
                raddr="$remote_addr"
                rport="0"
            fi
            [[ "$rport" == "*" ]] && rport="0"

            # Apply port filter
            if [[ -n "$filter_port" ]]; then
                [[ "$lport" != "$filter_port" && "$rport" != "$filter_port" ]] && continue
            fi

            # Parse PID/Program
            local pid=0 pname=""
            if [[ "$pid_prog" =~ ^([0-9]+)/(.+)$ ]]; then
                pid="${BASH_REMATCH[1]}"
                pname="${BASH_REMATCH[2]}"
            fi

            # Escape values
            local escaped_laddr escaped_raddr escaped_state escaped_pname
            escaped_laddr=$(_sysparse_escape_json "$laddr")
            escaped_raddr=$(_sysparse_escape_json "$raddr")
            escaped_state=$(_sysparse_escape_json "$state")
            escaped_pname=$(_sysparse_escape_json "$pname")

            results+=("{\"proto\":\"$proto\",\"local_addr\":\"$escaped_laddr\",\"local_port\":$lport,\"remote_addr\":\"$escaped_raddr\",\"remote_port\":$rport,\"state\":\"$escaped_state\",\"pid\":$pid,\"process\":\"$escaped_pname\"}")
            ((count++))
        done <<< "$net_output"
    fi

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_ss - Parse socket statistics to JSON
# =============================================================================
# @description Parse ss command output to JSON (Linux-specific, falls back to netstat)
# @pre        ss or netstat command available
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array
# @param      --listening - Only listening sockets
# @param      --tcp - Only TCP
# @param      --udp - Only UDP
# @param      --unix - Only Unix sockets
# @param      --summary - Show summary only
# @stdout     JSON array of socket objects
# @return     0 on success
#
# Usage: parse_ss --json --listening
# Usage: parse_ss --tcp --json
# =============================================================================
parse_ss() {
    local listening_only=0 tcp_only=0 udp_only=0 unix_only=0 summary_only=0
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --listening|-l)
                listening_only=1
                shift
                ;;
            --tcp|-t)
                tcp_only=1
                shift
                ;;
            --udp|-u)
                udp_only=1
                shift
                ;;
            --unix|-x)
                unix_only=1
                shift
                ;;
            --summary|-s)
                summary_only=1
                shift
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check for ss command
    if ! command -v ss &>/dev/null; then
        # Fall back to netstat via parse_netstat
        local netstat_args=()
        (( listening_only )) && netstat_args+=("--listening")
        (( tcp_only )) && netstat_args+=("--tcp")
        (( udp_only )) && netstat_args+=("--udp")
        netstat_args+=("--json")
        parse_netstat "${netstat_args[@]}"
        return $?
    fi

    # Handle summary mode
    if (( summary_only )); then
        local ss_summary
        ss_summary=$(ss -s 2>/dev/null) || {
            _sysparse_error "E_SS_FAILED" "Failed to execute ss -s"
            return 1
        }

        # Parse summary: Total: X TCP: Y (estab Z, closed W, ...)
        local total=0 tcp=0 udp=0 raw=0 inet=0 frag=0
        while IFS= read -r line; do
            if [[ "$line" =~ Total:[[:space:]]*([0-9]+) ]]; then
                total="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ TCP:[[:space:]]*([0-9]+) ]]; then
                tcp="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ UDP:[[:space:]]*([0-9]+) ]]; then
                udp="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ RAW:[[:space:]]*([0-9]+) ]]; then
                raw="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ INET:[[:space:]]*([0-9]+) ]]; then
                inet="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ FRAG:[[:space:]]*([0-9]+) ]]; then
                frag="${BASH_REMATCH[1]}"
            fi
        done <<< "$ss_summary"

        printf '{"total":%d,"tcp":%d,"udp":%d,"raw":%d,"inet":%d,"frag":%d}\n' \
            "$total" "$tcp" "$udp" "$raw" "$inet" "$frag"
        return 0
    fi

    # Build ss command options
    local ss_opts="-n"
    (( listening_only )) && ss_opts+="l"
    (( tcp_only )) && ss_opts+="t"
    (( udp_only )) && ss_opts+="u"
    (( unix_only )) && ss_opts+="x"
    [[ "$tcp_only" -eq 0 && "$udp_only" -eq 0 && "$unix_only" -eq 0 ]] && ss_opts+="a"
    ss_opts+="p"

    local ss_output
    ss_output=$(ss "$ss_opts" 2>/dev/null) || {
        _sysparse_error "E_SS_FAILED" "Failed to execute ss"
        return 1
    }

    while IFS= read -r line; do
        # Skip headers
        [[ "$line" =~ ^Netid ]] && continue
        [[ "$line" =~ ^State ]] && continue
        [[ -z "$line" ]] && continue

        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        # Parse based on socket type
        if (( unix_only )); then
            # Unix socket format: Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port
            local netid state recvq sendq local_path peer_path
            read -r netid state recvq sendq local_path peer_path <<< "$line"

            local escaped_local escaped_peer escaped_state
            escaped_local=$(_sysparse_escape_json "$local_path")
            escaped_peer=$(_sysparse_escape_json "$peer_path")
            escaped_state=$(_sysparse_escape_json "$state")

            results+=("{\"type\":\"unix\",\"state\":\"$escaped_state\",\"recv_q\":$recvq,\"send_q\":$sendq,\"local_path\":\"$escaped_local\",\"peer_path\":\"$escaped_peer\"}")
        else
            # TCP/UDP format - delegate to parse_netstat logic style
            local proto state recvq sendq local_addr peer_addr process_info
            if [[ "$line" =~ ^(tcp|udp) ]]; then
                read -r proto state recvq sendq local_addr peer_addr process_info <<< "$line"
            else
                read -r state recvq sendq local_addr peer_addr process_info <<< "$line"
                proto="tcp"
            fi

            # Parse addresses
            local laddr lport raddr rport
            if [[ "$local_addr" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
                laddr="${BASH_REMATCH[1]}"
                lport="${BASH_REMATCH[2]}"
            elif [[ "$local_addr" =~ ^(.+):([0-9*]+)$ ]]; then
                laddr="${BASH_REMATCH[1]}"
                lport="${BASH_REMATCH[2]}"
            else
                laddr="$local_addr"
                lport="0"
            fi
            [[ "$lport" == "*" ]] && lport="0"

            if [[ "$peer_addr" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
                raddr="${BASH_REMATCH[1]}"
                rport="${BASH_REMATCH[2]}"
            elif [[ "$peer_addr" =~ ^(.+):([0-9*]+)$ ]]; then
                raddr="${BASH_REMATCH[1]}"
                rport="${BASH_REMATCH[2]}"
            else
                raddr="$peer_addr"
                rport="0"
            fi
            [[ "$rport" == "*" ]] && rport="0"

            # Parse process info
            local pid=0 pname=""
            if [[ "$process_info" =~ pid=([0-9]+) ]]; then
                pid="${BASH_REMATCH[1]}"
            fi
            if [[ "$process_info" =~ \(\(\"([^\"]+)\" ]]; then
                pname="${BASH_REMATCH[1]}"
            fi

            local escaped_laddr escaped_raddr escaped_state escaped_pname
            escaped_laddr=$(_sysparse_escape_json "$laddr")
            escaped_raddr=$(_sysparse_escape_json "$raddr")
            escaped_state=$(_sysparse_escape_json "$state")
            escaped_pname=$(_sysparse_escape_json "$pname")

            results+=("{\"proto\":\"$proto\",\"state\":\"$escaped_state\",\"recv_q\":$recvq,\"send_q\":$sendq,\"local_addr\":\"$escaped_laddr\",\"local_port\":$lport,\"remote_addr\":\"$escaped_raddr\",\"remote_port\":$rport,\"pid\":$pid,\"process\":\"$escaped_pname\"}")
        fi
        ((count++))
    done <<< "$ss_output"

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_git_status - Parse git status to JSON
# =============================================================================
# @description Parse git status output to JSON
# @pre        Current directory is git repository
# @post       None
# @idempotent Yes
# @param      $1 [path] - Repository path (default: current dir)
# @param      --json - Output as JSON
# @stdout     JSON object with git status
# @return     0 on success, 1 if not a git repo
#
# Output: {"branch":"...","upstream":"...","ahead":N,"behind":N,
#          "staged":[...],"modified":[...],"untracked":[...],"conflicts":[...]}
#
# Usage: parse_git_status --json
# Usage: parse_git_status "/path/to/repo" --json
# =============================================================================
parse_git_status() {
    local path="${1:-.}"

    # Check if first arg is a flag
    if [[ "$path" == --* ]]; then
        path="."
    else
        shift || true
    fi

    # Verify it's a git repository
    if ! git -C "$path" rev-parse --git-dir &>/dev/null; then
        _sysparse_error "E_NOT_GIT_REPO" "Not a git repository" "$path"
        return 1
    fi

    # Get branch info
    local branch upstream ahead behind
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
    [[ -z "$branch" ]] && branch=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || echo "HEAD")

    upstream=$(git -C "$path" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")

    # Get ahead/behind counts
    ahead=0
    behind=0
    if [[ -n "$upstream" ]]; then
        local ab
        ab=$(git -C "$path" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || echo "0 0")
        read -r ahead behind <<< "$ab"
    fi

    # Parse git status --porcelain
    local -a staged=() modified=() untracked=() conflicts=()
    local git_status
    git_status=$(git -C "$path" status --porcelain 2>/dev/null) || {
        _sysparse_error "E_GIT_STATUS_FAILED" "Failed to get git status"
        return 1
    }

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local index_status="${line:0:1}"
        local worktree_status="${line:1:1}"
        local filename="${line:3}"

        # Escape filename for JSON
        local escaped_file
        escaped_file=$(_sysparse_escape_json "$filename")

        # Categorize changes
        case "${index_status}${worktree_status}" in
            "??")
                untracked+=("\"$escaped_file\"")
                ;;
            "UU"|"AA"|"DD"|"AU"|"UA"|"DU"|"UD")
                conflicts+=("\"$escaped_file\"")
                ;;
            *)
                # Check index (staged) changes
                case "$index_status" in
                    A|M|D|R|C)
                        staged+=("\"$escaped_file\"")
                        ;;
                esac
                # Check worktree (modified) changes
                case "$worktree_status" in
                    M|D)
                        modified+=("\"$escaped_file\"")
                        ;;
                esac
                ;;
        esac
    done <<< "$git_status"

    # Get remote URL (if any)
    local remote_url
    remote_url=$(git -C "$path" remote get-url origin 2>/dev/null || echo "")

    # Check if dirty
    local is_dirty=false
    if [[ ${#staged[@]} -gt 0 || ${#modified[@]} -gt 0 || ${#conflicts[@]} -gt 0 ]]; then
        is_dirty=true
    fi

    # Escape string values
    local escaped_branch escaped_upstream escaped_remote
    escaped_branch=$(_sysparse_escape_json "$branch")
    escaped_upstream=$(_sysparse_escape_json "$upstream")
    escaped_remote=$(_sysparse_escape_json "$remote_url")

    # Build JSON output
    printf '{"branch":"%s","upstream":"%s","ahead":%d,"behind":%d,"dirty":%s,"remote":"%s","staged":[%s],"modified":[%s],"untracked":[%s],"conflicts":[%s]}\n' \
        "$escaped_branch" \
        "$escaped_upstream" \
        "$ahead" \
        "$behind" \
        "$is_dirty" \
        "$escaped_remote" \
        "$(IFS=,; echo "${staged[*]}")" \
        "$(IFS=,; echo "${modified[*]}")" \
        "$(IFS=,; echo "${untracked[*]}")" \
        "$(IFS=,; echo "${conflicts[*]}")"
}

# =============================================================================
# parse_docker_ps - Parse docker containers to JSON
# =============================================================================
# @description Parse docker ps output to JSON
# @pre        Docker daemon running
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array
# @param      --all - Include stopped containers
# @param      --filter - Docker filter expression
# @stdout     JSON array of container objects
# @return     0 on success, 1 if docker not available
#
# Output: [{"id":"...","name":"...","image":"...","status":"...","ports":[...],"created":"ISO8601"}]
#
# Usage: parse_docker_ps --json
# Usage: parse_docker_ps --all --json
# =============================================================================
parse_docker_ps() {
    local show_all=0 filter=""
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                show_all=1
                shift
                ;;
            --filter|-f)
                filter="$2"
                shift 2
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check for docker command
    if ! command -v docker &>/dev/null; then
        _sysparse_error "E_DOCKER_NOT_FOUND" "Docker command not found"
        return 1
    fi

    # Check if docker daemon is running
    if ! docker info &>/dev/null; then
        _sysparse_error "E_DOCKER_NOT_RUNNING" "Docker daemon is not running"
        return 1
    fi

    # Build docker ps command with format template for reliable parsing
    local docker_format='{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}\t{{.State}}'
    local -a docker_args=("ps" "--format" "$docker_format")
    (( show_all )) && docker_args+=("-a")
    [[ -n "$filter" ]] && docker_args+=("--filter" "$filter")

    local docker_output
    docker_output=$(docker "${docker_args[@]}" 2>/dev/null) || {
        _sysparse_error "E_DOCKER_PS_FAILED" "Failed to execute docker ps"
        return 1
    }

    while IFS=$'\t' read -r id name image status ports created state; do
        [[ -z "$id" ]] && continue

        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        # Parse ports into array
        local -a port_list=()
        if [[ -n "$ports" ]]; then
            # Ports format: 0.0.0.0:8080->80/tcp, ...
            local IFS=','
            for port_entry in $ports; do
                port_entry="${port_entry# }"  # Trim leading space
                local escaped_port
                escaped_port=$(_sysparse_escape_json "$port_entry")
                port_list+=("\"$escaped_port\"")
            done
        fi

        # Escape values
        local escaped_id escaped_name escaped_image escaped_status escaped_created escaped_state
        escaped_id=$(_sysparse_escape_json "$id")
        escaped_name=$(_sysparse_escape_json "$name")
        escaped_image=$(_sysparse_escape_json "$image")
        escaped_status=$(_sysparse_escape_json "$status")
        escaped_created=$(_sysparse_escape_json "$created")
        escaped_state=$(_sysparse_escape_json "$state")

        results+=("{\"id\":\"$escaped_id\",\"name\":\"$escaped_name\",\"image\":\"$escaped_image\",\"status\":\"$escaped_status\",\"state\":\"$escaped_state\",\"created\":\"$escaped_created\",\"ports\":[$(IFS=,; echo "${port_list[*]}")]}")
        ((count++))
    done <<< "$docker_output"

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_npm_list - Parse npm packages to JSON
# =============================================================================
# @description Parse npm list output to JSON
# @pre        npm command available, package.json exists
# @post       None
# @idempotent Yes
# @param      $1 [path] - Project path (default: current dir)
# @param      --json - Output as JSON array
# @param      --depth - Dependency depth (default: 0 = direct deps only)
# @param      --dev - Include devDependencies
# @param      --prod - Only production dependencies
# @stdout     JSON array of package objects
# @return     0 on success, 1 if npm not available or no package.json
#
# Output: [{"name":"...","version":"...","type":"prod|dev","path":"..."}]
#
# Usage: parse_npm_list --json
# Usage: parse_npm_list "/path/to/project" --depth 1 --json
# =============================================================================
parse_npm_list() {
    local path="${1:-.}"
    local depth=0 include_dev=1 prod_only=0

    # Check if first arg is a flag
    if [[ "$path" == --* ]]; then
        path="."
    else
        shift || true
    fi

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --depth)
                depth="$2"
                shift 2
                ;;
            --dev)
                include_dev=1
                shift
                ;;
            --prod)
                prod_only=1
                shift
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Validate depth
    if [[ ! "$depth" =~ ^[0-9]+$ ]]; then
        _sysparse_error "E_INVALID_DEPTH" "Depth must be a number" "$depth"
        return 1
    fi

    # Check for npm command
    if ! command -v npm &>/dev/null; then
        _sysparse_error "E_NPM_NOT_FOUND" "npm command not found"
        return 1
    fi

    # Check for package.json
    if [[ ! -f "$path/package.json" ]]; then
        _sysparse_error "E_NO_PACKAGE_JSON" "No package.json found" "$path"
        return 1
    fi

    # Build npm list arguments
    local -a npm_args=("list" "--json" "--depth" "$depth")
    (( prod_only )) && npm_args+=("--prod")

    local npm_output
    npm_output=$(cd "$path" && npm "${npm_args[@]}" 2>/dev/null) || {
        # npm list may return non-zero for missing deps - try to parse anyway
        npm_output=$(cd "$path" && npm "${npm_args[@]}" 2>&1 | grep -v '^npm' || echo '{}')
    }

    # Parse npm JSON output
    local count=0
    local -a results=()

    # Extract dependencies recursively using simple parsing
    # npm list --json format: {"dependencies":{"pkg":{"version":"x.x.x","dependencies":{...}}}}
    _parse_npm_deps() {
        local json="$1"
        local pkg_type="${2:-prod}"
        local prefix="${3:-}"

        # Extract package names using regex
        local pattern='"([^"]+)"[[:space:]]*:[[:space:]]*\{[^}]*"version"[[:space:]]*:[[:space:]]*"([^"]+)"'

        while [[ "$json" =~ $pattern ]]; do
            local pkg_name="${BASH_REMATCH[1]}"
            local pkg_version="${BASH_REMATCH[2]}"

            # Skip internal keys
            [[ "$pkg_name" =~ ^(dependencies|devDependencies|name|version)$ ]] && {
                json="${json#*"${BASH_REMATCH[0]}"}"
                continue
            }

            if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
                break
            fi

            local escaped_name escaped_version
            escaped_name=$(_sysparse_escape_json "$pkg_name")
            escaped_version=$(_sysparse_escape_json "$pkg_version")

            results+=("{\"name\":\"$escaped_name\",\"version\":\"$escaped_version\",\"type\":\"$pkg_type\"}")
            ((count++))

            # Remove matched portion and continue
            json="${json#*"${BASH_REMATCH[0]}"}"
        done
    }

    # Parse dependencies
    if [[ "$npm_output" =~ \"dependencies\"[[:space:]]*:[[:space:]]*\{ ]]; then
        _parse_npm_deps "$npm_output" "prod"
    fi

    # Parse devDependencies if included
    if (( include_dev && ! prod_only )) && [[ "$npm_output" =~ \"devDependencies\"[[:space:]]*:[[:space:]]*\{ ]]; then
        _parse_npm_deps "$npm_output" "dev"
    fi

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_pip_list - Parse pip packages to JSON
# =============================================================================
# @description Parse pip list output to JSON
# @pre        pip/pip3 command available
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON array
# @param      --outdated - Show only outdated packages
# @param      --user - Show only user-installed packages
# @stdout     JSON array of package objects
# @return     0 on success, 1 if pip not available
#
# Output: [{"name":"...","version":"...","latest":"..."}]
#
# Usage: parse_pip_list --json
# Usage: parse_pip_list --outdated --json
# =============================================================================
parse_pip_list() {
    local show_outdated=0 user_only=0
    local count=0
    local -a results=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --outdated|-o)
                show_outdated=1
                shift
                ;;
            --user|-u)
                user_only=1
                shift
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Find pip command
    local pip_cmd=""
    if command -v pip3 &>/dev/null; then
        pip_cmd="pip3"
    elif command -v pip &>/dev/null; then
        pip_cmd="pip"
    else
        _sysparse_error "E_PIP_NOT_FOUND" "pip/pip3 command not found"
        return 1
    fi

    # Build pip list arguments
    local -a pip_args=("list" "--format=json")
    (( show_outdated )) && pip_args+=("--outdated")
    (( user_only )) && pip_args+=("--user")

    local pip_output
    pip_output=$("$pip_cmd" "${pip_args[@]}" 2>/dev/null) || {
        _sysparse_error "E_PIP_LIST_FAILED" "Failed to execute pip list"
        return 1
    }

    # pip list --format=json outputs: [{"name":"pkg","version":"x.x.x"},...]
    # For outdated: [{"name":"pkg","version":"x.x.x","latest_version":"y.y.y"},...]

    # Parse JSON - pip already gives us JSON, we just need to restructure
    # Extract each package using regex
    local pattern='\{"name"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)"'

    while [[ "$pip_output" =~ $pattern ]]; do
        local pkg_name="${BASH_REMATCH[1]}"
        local pkg_version="${BASH_REMATCH[2]}"

        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        local escaped_name escaped_version
        escaped_name=$(_sysparse_escape_json "$pkg_name")
        escaped_version=$(_sysparse_escape_json "$pkg_version")

        # Check for latest_version if outdated
        local latest=""
        local match_text="${BASH_REMATCH[0]}"
        local rest="${pip_output#*"$match_text"}"
        if [[ "$rest" =~ ^[^\}]*\"latest_version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            latest="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$latest" ]]; then
            local escaped_latest
            escaped_latest=$(_sysparse_escape_json "$latest")
            results+=("{\"name\":\"$escaped_name\",\"version\":\"$escaped_version\",\"latest\":\"$escaped_latest\"}")
        else
            results+=("{\"name\":\"$escaped_name\",\"version\":\"$escaped_version\"}")
        fi
        ((count++))

        # Remove matched portion
        pip_output="${pip_output#*"$match_text"}"
    done

    _sysparse_join_array "${results[@]}"
    printf '\n'
}

# =============================================================================
# parse_env - Parse environment to JSON
# =============================================================================
# @description Parse environment variables to JSON
# @pre        None
# @post       None
# @idempotent Yes
# @param      --json - Output as JSON object
# @param      --prefix - Filter by variable prefix
# @param      --pattern - Filter by regex pattern
# @param      --redact - Redact sensitive values (API keys, passwords)
# @stdout     JSON object of environment variables
# @return     0 on success
#
# Output: {"VAR_NAME":"value",...}
#
# Usage: parse_env --json
# Usage: parse_env --prefix MAINFRAME_ --json
# Usage: parse_env --redact --json
# =============================================================================
parse_env() {
    local prefix="" pattern="" redact=0
    local count=0
    local first=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix|-p)
                prefix="$2"
                shift 2
                ;;
            --pattern)
                pattern="$2"
                shift 2
                ;;
            --redact|-r)
                redact=1
                shift
                ;;
            --json)
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Patterns for sensitive values that should be redacted
    local -a sensitive_patterns=(
        "PASSWORD"
        "SECRET"
        "TOKEN"
        "API_KEY"
        "APIKEY"
        "PRIVATE_KEY"
        "CREDENTIAL"
        "AUTH"
        "_KEY$"
        "ACCESS_KEY"
    )

    printf '{'
    while IFS='=' read -r name value; do
        [[ -z "$name" ]] && continue

        # Enforce truncation limit
        if (( count >= MAINFRAME_SYSPARSE_TRUNCATE )); then
            break
        fi

        # Apply prefix filter
        if [[ -n "$prefix" && "$name" != "$prefix"* ]]; then
            continue
        fi

        # Apply pattern filter
        if [[ -n "$pattern" && ! "$name" =~ $pattern ]]; then
            continue
        fi

        # Check if value should be redacted
        local display_value="$value"
        if (( redact )); then
            local name_upper="${name^^}"
            for sens_pattern in "${sensitive_patterns[@]}"; do
                if [[ "$name_upper" =~ $sens_pattern ]]; then
                    display_value="[REDACTED]"
                    break
                fi
            done
        fi

        # Escape values
        local escaped_name escaped_value
        escaped_name=$(_sysparse_escape_json "$name")
        escaped_value=$(_sysparse_escape_json "$display_value")

        $first || printf ','
        first=false
        printf '"%s":"%s"' "$escaped_name" "$escaped_value"
        ((count++))
    done < <(env | sort)
    printf '}\n'
}

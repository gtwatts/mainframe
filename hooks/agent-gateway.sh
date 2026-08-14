#!/usr/bin/env bash
# =============================================================================
# MAINFRAME Enforced Agent Gateway
# =============================================================================
# Pre-tool hook for shell-capable coding agents. The gateway accepts the
# current Codex, Claude Code, GitHub Copilot CLI, and Gemini CLI payload shapes,
# classifies shell commands with Mainframe's canonical destructive-command
# gate, and exits 2 when policy denies execution. Those hosts interpret exit 2
# from their pre-tool hook as a block.
#
# The gateway is deliberately fail-closed for malformed hook input, a missing
# JSON parser, or an unavailable audit trail. It is a policy hook, not a shell
# sandbox; commands that pass still execute with the host agent's privileges.
# =============================================================================

# The generated host bindings invoke this script with Bash privileged mode.
# That mode suppresses BASH_ENV/ENV processing, imported shell functions, and
# other startup-state inheritance before any gateway code can run.
case "$-" in
    *p*) ;;
    *)
        printf 'MAINFRAME agent gateway requires a privileged clean Bash entrypoint. Tool call denied.\n' >&2
        exit 2
        ;;
esac

set -uo pipefail

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
readonly PATH

# Codex, Claude Code, and Gemini distinguish the blocking exit code (2) from
# ordinary hook failures. Convert every unexpected non-zero termination into a
# denial so a missing dependency or runtime error cannot become an allow.
gateway_exit_guard() {
    local exit_code=$?
    trap - EXIT
    if (( exit_code != 0 && exit_code != 2 )); then
        printf 'MAINFRAME agent gateway blocked the tool call: internal gateway failure (exit=%d)\n' \
            "$exit_code" >&2
        exit 2
    fi
    exit "$exit_code"
}
trap gateway_exit_guard EXIT

if (( BASH_VERSINFO[0] < 4 )) || \
   (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4 )); then
    printf 'MAINFRAME agent gateway requires Bash 4.4+ (found %s). Tool call denied.\n' \
        "$BASH_VERSION" >&2
    exit 2
fi

GATE_JQ="${MAINFRAME_AGENT_JQ:-}"
if [[ "$GATE_JQ" != /* || ! -f "$GATE_JQ" || -L "$GATE_JQ" || ! -x "$GATE_JQ" ||
      "$GATE_JQ" == *$'\n'* || "$GATE_JQ" == *$'\r'* || "$GATE_JQ" == *$'\t'* ]]; then
    printf 'MAINFRAME agent gateway blocked the tool call: trusted jq binding is missing or unsafe\n' >&2
    exit 2
fi
readonly GATE_JQ

GATE_SAFETY="${MAINFRAME_AGENT_SAFETY:-}"
if [[ "$GATE_SAFETY" != /* || ! -f "$GATE_SAFETY" || -L "$GATE_SAFETY" ||
      ! -r "$GATE_SAFETY" || "$GATE_SAFETY" == *$'\n'* ||
      "$GATE_SAFETY" == *$'\r'* || "$GATE_SAFETY" == *$'\t'* ]]; then
    printf 'MAINFRAME agent gateway blocked the tool call: trusted safety policy binding is missing or unsafe\n' >&2
    exit 2
fi
readonly GATE_SAFETY

gateway_block_error() {
    printf 'MAINFRAME agent gateway blocked the tool call: %s\n' "$1" >&2
    exit 2
}

gateway_audit_path_is_canonical() {
    local candidate="$1" component
    local -a components=()

    [[ "$candidate" == /* && "$candidate" != */ &&
       "$candidate" != *$'\n'* && "$candidate" != *$'\r'* &&
       "$candidate" != *$'\t'* ]] || return 1
    IFS='/' read -r -a components <<<"$candidate"
    for component in "${components[@]}"; do
        case "$component" in
            '' ) ;;
            .|..) return 1 ;;
        esac
    done
}

gateway_audit_dir_is_safe() {
    local directory="$1" cursor="/" component
    local -a components=()

    [[ "$directory" == /* ]] || return 1
    IFS='/' read -r -a components <<<"$directory"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        cursor="${cursor%/}/$component"
        if [[ -e "$cursor" || -L "$cursor" ]]; then
            if [[ -L "$cursor" ]]; then
                # macOS exposes its real temporary hierarchy through these
                # root-owned compatibility links. Permit only these exact
                # platform links; user-controlled ancestors still fail.
                case "$cursor:$(readlink "$cursor" 2>/dev/null)" in
                    /tmp:private/tmp|/var:private/var) continue ;;
                    *) return 1 ;;
                esac
            fi
            [[ -d "$cursor" ]] || return 1
        fi
    done
}

gateway_stat_mode() {
    case "$(/usr/bin/uname -s 2>/dev/null)" in
        Darwin) /usr/bin/stat -f '%Lp' "$1" 2>/dev/null ;;
        *) /usr/bin/stat -c '%a' "$1" 2>/dev/null ;;
    esac
}

gateway_stat_links() {
    case "$(/usr/bin/uname -s 2>/dev/null)" in
        Darwin) /usr/bin/stat -f '%l' "$1" 2>/dev/null ;;
        *) /usr/bin/stat -c '%h' "$1" 2>/dev/null ;;
    esac
}

gateway_stat_identity() {
    case "$(/usr/bin/uname -s 2>/dev/null)" in
        # macOS fdesc reports a synthetic device number for /dev/fd/N even
        # when the descriptor and pathname reference the same inode.
        Darwin) /usr/bin/stat -f '%i' "$1" 2>/dev/null ;;
        # GNU stat otherwise reports the /dev/fd symlink itself. Dereference
        # it and retain the device number so two filesystems cannot collide on
        # inode alone.
        *) /usr/bin/stat -L -c '%d:%i' "$1" 2>/dev/null ;;
    esac
}

gateway_audit_dir_permissions_are_safe() {
    local directory="$1" mode
    mode="$(gateway_stat_mode "$directory")" || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 0022) == 0 ))
}

gateway_audit_file_has_one_link() {
    local links
    links="$(gateway_stat_links "$1")" || return 1
    [[ "$links" == 1 ]]
}

gateway_audit_target_is_current() {
    local path_identity fd_identity
    [[ -f "$gateway_audit_log" && ! -L "$gateway_audit_log" &&
       -O "$gateway_audit_log" ]] || return 1
    gateway_audit_file_has_one_link "$gateway_audit_log" || return 1
    path_identity="$(gateway_stat_identity "$gateway_audit_log")" || return 1
    fd_identity="$(gateway_stat_identity "/dev/fd/$GATE_AUDIT_FD")" || return 1
    [[ -n "$path_identity" && "$path_identity" == "$fd_identity" ]]
}

gateway_usage() {
    cat <<'EOF'
Usage: mainframe agent-hook [--format auto|codex|claude|copilot|gemini]

Read a pre-tool hook payload from stdin and enforce Mainframe's destructive
command policy. Safe and non-shell tool calls emit {} and exit 0. Denied or
malformed calls exit 2 so supported hosts block the tool invocation.

Environment:
  MAINFRAME_AGENT_GATE_TIER   critical|high|medium (default: medium)
  MAINFRAME_AGENT_AUDIT_LOG   JSONL decision log path
EOF
}

format="auto"
while (( $# > 0 )); do
    case "$1" in
        --format)
            (( $# >= 2 )) || { gateway_usage >&2; exit 64; }
            format="$2"
            shift 2
            ;;
        --format=*)
            format="${1#*=}"
            shift
            ;;
        -h|--help)
            gateway_usage
            exit 0
            ;;
        *)
            printf 'Unknown agent-hook option: %s\n' "$1" >&2
            gateway_usage >&2
            exit 64
            ;;
    esac
done

case "$format" in
    auto|codex|claude|copilot|gemini) ;;
    *)
        printf 'Unsupported agent-hook format: %s\n' "$format" >&2
        exit 64
        ;;
esac

# Read the hook payload from the inherited descriptor itself. Reopening
# /dev/stdin fails with ENXIO on Linux when the host supplies stdin through an
# anonymous pipe, even though that already-open descriptor remains readable.
payload=""
payload_delimiter_seen=false
IFS= read -r -d '' payload <&0 && payload_delimiter_seen=true
[[ "$payload_delimiter_seen" == false ]] || gateway_block_error "malformed JSON hook payload"
[[ -n "$payload" ]] || gateway_block_error "empty hook payload"
"$GATE_JQ" -e 'type == "object"' >/dev/null 2>&1 <<<"$payload" || \
    gateway_block_error "malformed JSON hook payload"

# Resolve a private, durable audit path before sourcing the safety library so
# its AGENT_AUDIT_LOG default cannot fall back to a per-process /tmp file.
if [[ -n "${MAINFRAME_AGENT_AUDIT_LOG:-}" ]]; then
    gateway_audit_log="$MAINFRAME_AGENT_AUDIT_LOG"
elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    gateway_audit_log="$XDG_STATE_HOME/mainframe/agent-gateway.jsonl"
elif [[ -n "${HOME:-}" ]]; then
    gateway_audit_log="$HOME/.local/state/mainframe/agent-gateway.jsonl"
else
    gateway_audit_log="/tmp/mainframe-${UID:-user}/agent-gateway.jsonl"
fi

gateway_audit_path_is_canonical "$gateway_audit_log" || \
    gateway_block_error "audit log must be a canonical absolute path"
gateway_audit_dir="$(dirname "$gateway_audit_log")"
gateway_audit_dir_is_safe "$gateway_audit_dir" || \
    gateway_block_error "audit directory contains a symbolic-link or non-directory ancestor"
[[ ! -L "$gateway_audit_log" ]] || gateway_block_error "audit log may not be a symbolic link"
umask 077
mkdir -p "$gateway_audit_dir" 2>/dev/null || \
    gateway_block_error "cannot create the audit directory"
gateway_audit_dir_is_safe "$gateway_audit_dir" || \
    gateway_block_error "audit directory became unsafe during creation"
[[ -d "$gateway_audit_dir" && -O "$gateway_audit_dir" ]] || \
    gateway_block_error "audit directory is not owned by the current user"
gateway_audit_dir_permissions_are_safe "$gateway_audit_dir" || \
    gateway_block_error "audit directory is writable by group or other users"
if [[ -e "$gateway_audit_log" ]]; then
    [[ -f "$gateway_audit_log" && ! -L "$gateway_audit_log" &&
       -O "$gateway_audit_log" ]] || \
        gateway_block_error "audit log is not a safe user-owned regular file"
    gateway_audit_file_has_one_link "$gateway_audit_log" || \
        gateway_block_error "audit log must have exactly one hard link"
fi
: >>"$gateway_audit_log" 2>/dev/null || gateway_block_error "cannot write the audit log"
gateway_audit_file_has_one_link "$gateway_audit_log" || \
    gateway_block_error "audit log must have exactly one hard link"
chmod 600 "$gateway_audit_log" 2>/dev/null || gateway_block_error "cannot secure the audit log"
[[ -f "$gateway_audit_log" && ! -L "$gateway_audit_log" &&
   -O "$gateway_audit_log" ]] || \
    gateway_block_error "audit log became unsafe during creation"
exec {GATE_AUDIT_FD}>>"$gateway_audit_log" || \
    gateway_block_error "cannot open the audit log for append"
gateway_audit_target_is_current || \
    gateway_block_error "audit log changed while opening the decision stream"
export AGENT_AUDIT_LOG="$gateway_audit_log"
export AGENT_AUDIT_FD="$GATE_AUDIT_FD"

# The gateway uses the canonical rule set directly rather than copying host-
# specific regexes. This keeps CLI hooks, safe_exec, and future adapters in
# lockstep as policy evolves.
# shellcheck source=lib/agent_safety.sh
source "$GATE_SAFETY"

payload_shape="snake"
if "$GATE_JQ" -e 'has("toolName") or has("toolArgs")' >/dev/null 2>&1 <<<"$payload"; then
    payload_shape="camel"
fi

event_name=""
tool_name=""
command_text=""
host_name=""
tool_args_json=""

if [[ "$payload_shape" == "camel" ]]; then
    [[ "$format" == "auto" || "$format" == "copilot" ]] || \
        gateway_block_error "camelCase hook input is only valid for Copilot"

    host_name="copilot"
    event_name="$("$GATE_JQ" -r '.hookEventName // .hook_event_name // "PreToolUse"' <<<"$payload")"
    tool_name="$("$GATE_JQ" -er '.toolName | select(type == "string" and length > 0)' <<<"$payload" 2>/dev/null)" || \
        gateway_block_error "missing string toolName"
else
    event_name="$("$GATE_JQ" -er '.hook_event_name | select(type == "string" and length > 0)' <<<"$payload" 2>/dev/null)" || \
        gateway_block_error "missing string hook_event_name"
    tool_name="$("$GATE_JQ" -er '.tool_name | select(type == "string" and length > 0)' <<<"$payload" 2>/dev/null)" || \
        gateway_block_error "missing string tool_name"

    case "$format:$event_name" in
        auto:PreToolUse|claude:PreToolUse) host_name="claude" ;;
        codex:PreToolUse) host_name="codex" ;;
        copilot:PreToolUse) host_name="copilot" ;;
        auto:BeforeTool|gemini:BeforeTool) host_name="gemini" ;;
        *) gateway_block_error "unexpected event '$event_name' for format '$format'" ;;
    esac
fi

# Bash case conversion avoids an external transformation whose failure could
# otherwise turn a shell tool into the non-shell allow path.
tool_key="${tool_name,,}"
case "$tool_key" in
    powershell)
        gateway_block_error "PowerShell is outside the POSIX shell policy scope"
        ;;
    bash|shell|run_shell_command|run_terminal_command|exec_command)
        if [[ "$payload_shape" == "camel" ]]; then
            # Copilot's native hook schema serializes toolArgs as a JSON
            # string. Accept an object as well for SDK adapters that have
            # already decoded it, but reject every other representation.
            tool_args_json="$("$GATE_JQ" -cer '
                if (.toolArgs | type) == "string" then
                    (.toolArgs | fromjson | select(type == "object"))
                else
                    (.toolArgs | select(type == "object"))
                end
            ' <<<"$payload" 2>/dev/null)" || \
                gateway_block_error "shell tool '$tool_name' has invalid toolArgs JSON"
            command_text="$("$GATE_JQ" -er '
                (.command // .cmd) |
                select(type == "string" and length > 0)
            ' <<<"$tool_args_json" 2>/dev/null)" || \
                gateway_block_error "shell tool '$tool_name' is missing a string command"
        else
            command_text="$("$GATE_JQ" -er '
                (.tool_input.command // .tool_input.cmd) |
                select(type == "string" and length > 0)
            ' <<<"$payload" 2>/dev/null)" || \
                gateway_block_error "shell tool '$tool_name' is missing a string command"
        fi
        ;;
    *)
        if ! agent_audit "agent_gateway_decision" \
            "host=$host_name" "event=$event_name" "tool=$tool_name" \
            "risk=none" "rule=non-shell-tool" "decision=allow"; then
            gateway_block_error "cannot append the audit decision"
        fi
        gateway_audit_target_is_current || \
            gateway_block_error "audit log changed after the decision write"
        printf '{}\n'
        exit 0
        ;;
esac

export AGENT_GATE_BLOCK_TIER="${MAINFRAME_AGENT_GATE_TIER:-medium}"
case "$AGENT_GATE_BLOCK_TIER" in
    critical|high|medium) ;;
    *) gateway_block_error "invalid MAINFRAME_AGENT_GATE_TIER '$AGENT_GATE_BLOCK_TIER'" ;;
esac

classification="$(agent_gate_classify "$command_text")" || \
    gateway_block_error "command classification failed"
risk="$("$GATE_JQ" -er '.risk' <<<"$classification" 2>/dev/null)" || \
    gateway_block_error "invalid classifier result"
rule="$("$GATE_JQ" -er '.rule' <<<"$classification" 2>/dev/null)" || \
    gateway_block_error "invalid classifier result"
blocked="$("$GATE_JQ" -er \
    '.blocked | select(type == "boolean") | tostring' \
    <<<"$classification" 2>/dev/null)" || \
    gateway_block_error "invalid classifier result"
case "$blocked" in
    true|false) ;;
    *) gateway_block_error "invalid classifier result" ;;
esac

decision="allow"
[[ "$blocked" == "true" ]] && decision="deny"

if ! agent_audit "agent_gateway_decision" \
    "host=$host_name" "event=$event_name" "tool=$tool_name" \
    "risk=$risk" "rule=$rule" "decision=$decision"; then
    gateway_block_error "cannot append the audit decision"
fi
gateway_audit_target_is_current || \
    gateway_block_error "audit log changed after the decision write"

if [[ "$blocked" == "true" ]]; then
    gateway_block_error "risk=$risk rule=$rule"
fi

printf '{}\n'

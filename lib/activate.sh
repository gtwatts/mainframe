#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/activate.sh - Explicit, merge-safe host activation (Phase 1)
# =============================================================================
# Implements `mainframe activate|deactivate|activate status`.
#
# Rules (A++ Phase 1 deliverables 1-2):
#   * --dry-run prints intended changes and writes nothing
#   * never overwrite an existing instruction file
#   * activation content lives inside BEGIN/END markers; deactivation removes
#     only MAINFRAME-managed content
#   * idempotent: activating twice reports already-current
# =============================================================================

_MAINFRAME_ACTIVATE_MARKER_TAG="MAINFRAME"

# This bootstrap is the only command interpreted by the host hook shell. It
# starts Apple's/system Bash in privileged mode before consulting any inherited
# function or BASH_ENV state, validates the five-value launch-time contract,
# rehashes its four bound runtime artifacts, and normalizes every gateway
# failure to the hosts' blocking exit code. Keep the
# body compatible with macOS Bash 3.2 and free of single quotes so the exact
# command can remain machine-independent in project configuration.
_MAINFRAME_AGENT_HOOK_BOOTSTRAP='hook_format=$1; case ${MAINFRAME_AGENT_BASH-} in /*) ;; *) exit 2;; esac; case ${MAINFRAME_AGENT_JQ-} in /*) ;; *) exit 2;; esac; case ${MAINFRAME_AGENT_GATEWAY-} in /*) ;; *) exit 2;; esac; case ${MAINFRAME_AGENT_SAFETY-} in /*) ;; *) exit 2;; esac; PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; seal=${MAINFRAME_AGENT_SEAL-}; bash_sha=${seal%%:*}; rest=${seal#*:}; jq_sha=${rest%%:*}; rest=${rest#*:}; gateway_sha=${rest%%:*}; safety_sha=${rest#*:}; [ "$safety_sha" != "$rest" ] || exit 2; mf_digest(){ [ ${#1} -eq 64 ] || return 1; case $1 in *[!0-9a-f]*) return 1;; esac; }; mf_hash(){ mf_digest "$2" || return 1; if [ -x /usr/bin/sha256sum ]; then out=$(/usr/bin/sha256sum "$1") || return 1; actual=${out%% *}; elif [ -x /bin/sha256sum ]; then out=$(/bin/sha256sum "$1") || return 1; actual=${out%% *}; elif [ -x /usr/bin/shasum ]; then out=$(/usr/bin/shasum -a 256 "$1") || return 1; actual=${out%% *}; elif [ -x /usr/bin/openssl ]; then out=$(/usr/bin/openssl dgst -sha256 "$1") || return 1; actual=${out##* }; elif [ -x /bin/openssl ]; then out=$(/bin/openssl dgst -sha256 "$1") || return 1; actual=${out##* }; else return 1; fi; [ "$actual" = "$2" ]; }; mf_hash "$MAINFRAME_AGENT_BASH" "$bash_sha" || exit 2; mf_hash "$MAINFRAME_AGENT_JQ" "$jq_sha" || exit 2; mf_hash "$MAINFRAME_AGENT_GATEWAY" "$gateway_sha" || exit 2; mf_hash "$MAINFRAME_AGENT_SAFETY" "$safety_sha" || exit 2; if MAINFRAME_AGENT_JQ="$MAINFRAME_AGENT_JQ" MAINFRAME_AGENT_SAFETY="$MAINFRAME_AGENT_SAFETY" "$MAINFRAME_AGENT_BASH" --noprofile --norc -p "$MAINFRAME_AGENT_GATEWAY" --format "$hook_format"; then exit 0; else exit 2; fi'

# host -> project-relative instruction file
_mainframe_activate_hosts() {
    cat <<'EOF'
codex	AGENTS.md
claude-code	CLAUDE.md
copilot	.github/copilot-instructions.md
gemini	GEMINI.md
cursor	.cursor/rules/mainframe.mdc
jetbrains	.aiassistant/rules/mainframe.md
junie	.junie/guidelines.md
EOF
}

_mainframe_activate_file_for() {
    local host="$1"
    _mainframe_activate_hosts | awk -F'\t' -v h="$host" '$1 == h {print $2; found=1} END {exit !found}'
}

_mainframe_activate_known_hosts() {
    _mainframe_activate_hosts | awk -F'\t' '{print $1}'
}

# Resolve the project once, before composing any managed path. All subsequent
# checks are relative to this physical root so a lexical --project path cannot
# make a nested host path appear project-scoped when it is not.
_mainframe_activate_project_root() {
    local project="$1"

    if [[ ! -d "$project" ]]; then
        echo "Project directory not found: $project" >&2
        return 1
    fi
    (cd "$project" && pwd -P)
}

# Reject symbolic links in both the final managed file and every project-local
# parent component. Agent repositories are untrusted input; `.claude ->
# ~/.claude` and `AGENTS.md -> elsewhere` must never turn project activation
# into an out-of-project write.
_mainframe_activate_validate_managed_path() {
    local project="$1" rel="$2" cursor component file index
    local -a parts=()

    case "$rel" in
        ""|/*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*//* )
            echo "Unsafe managed project path: $rel" >&2
            return 1
            ;;
    esac

    IFS='/' read -r -a parts <<< "$rel"
    cursor="$project"
    for ((index = 0; index < ${#parts[@]} - 1; index++)); do
        component="${parts[$index]}"
        cursor="$cursor/$component"
        if [[ -L "$cursor" ]]; then
            echo "Refusing symbolic-link parent in managed project path: $cursor" >&2
            return 1
        fi
        if [[ -e "$cursor" && ! -d "$cursor" ]]; then
            echo "Managed project path parent is not a directory: $cursor" >&2
            return 1
        fi
    done

    file="$project/$rel"
    if [[ -L "$file" ]]; then
        echo "Refusing symbolic-link managed project file: $file" >&2
        return 1
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        echo "Managed project path is not a regular file: $file" >&2
        return 1
    fi
}

_mainframe_activate_paths_preflight() {
    local project="$1" enforce="$2" host rel
    shift 2

    for host in "$@"; do
        rel="$(_mainframe_activate_file_for "$host")" || return 1
        _mainframe_activate_validate_managed_path "$project" "$rel" || return 1
        if [[ "$enforce" == "true" ]] && _mainframe_enforce_supported "$host"; then
            rel="$(_mainframe_enforce_file_for "$host")" || return 1
            _mainframe_activate_validate_managed_path "$project" "$rel" || return 1
        fi
    done
}

# Hosts with a supported pre-tool enforcement hook. Instruction activation is
# available for every host above; enforcement is deliberately opt-in because
# it changes whether the host is allowed to execute a command.
_mainframe_enforce_hosts() {
    cat <<'EOF'
codex	.codex/hooks.json
claude-code	.claude/settings.json
copilot	.github/hooks/mainframe.json
gemini	.gemini/settings.json
EOF
}

_mainframe_enforce_file_for() {
    local host="$1"
    _mainframe_enforce_hosts | awk -F'\t' -v h="$host" '$1 == h {print $2; found=1} END {exit !found}'
}

_mainframe_enforce_supported() {
    _mainframe_enforce_file_for "$1" >/dev/null 2>&1
}

_mainframe_enforce_command_for() {
    local host="$1" format

    case "$host" in
        codex) format=codex ;;
        claude-code) format=claude ;;
        copilot) format=copilot ;;
        gemini) format=gemini ;;
        *) return 1 ;;
    esac

    printf "/bin/bash -p -c '%s' mainframe-agent-hook %s\n" \
        "$_MAINFRAME_AGENT_HOOK_BOOTSTRAP" "$format"
}

# Resolve the machine-local privileged gateway dependencies without placing
# their private/versioned paths in commit-safe project configuration. Launch
# exports these exact bindings to the selected host process; a direct host
# start without them fails closed at hook invocation.
declare -g _MAINFRAME_ENFORCE_BIND_ERROR=""

_mainframe_enforce_bind_fail() {
    _MAINFRAME_ENFORCE_BIND_ERROR="$1"
    unset MAINFRAME_AGENT_BASH MAINFRAME_AGENT_JQ MAINFRAME_AGENT_GATEWAY \
        MAINFRAME_AGENT_SAFETY MAINFRAME_AGENT_SEAL
    return 1
}

_mainframe_enforce_sha256_file() {
    local file="$1" output digest

    if [[ -x /usr/bin/sha256sum ]]; then
        output="$(/usr/bin/sha256sum "$file")" || return 1
        digest="${output%% *}"
    elif [[ -x /bin/sha256sum ]]; then
        output="$(/bin/sha256sum "$file")" || return 1
        digest="${output%% *}"
    elif [[ -x /usr/bin/shasum ]]; then
        output="$(/usr/bin/shasum -a 256 "$file")" || return 1
        digest="${output%% *}"
    elif [[ -x /usr/bin/openssl ]]; then
        output="$(/usr/bin/openssl dgst -sha256 "$file")" || return 1
        digest="${output##* }"
    elif [[ -x /bin/openssl ]]; then
        output="$(/bin/openssl dgst -sha256 "$file")" || return 1
        digest="${output##* }"
    else
        return 1
    fi
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

_mainframe_enforce_bind_jq() {
    local project="$1" search_path jq_candidate jq_path

    if (( $# >= 2 )); then
        search_path="$2"
    else
        search_path="${_MAINFRAME_AGENT_DISCOVERY_PATH-${PATH:-}}"
    fi

    unset MAINFRAME_AGENT_JQ
    jq_candidate="$(PATH="$search_path" type -P jq 2>/dev/null || true)"
    [[ -n "$jq_candidate" && "$jq_candidate" == /* ]] || {
        _mainframe_enforce_bind_fail 'jq was not found as an absolute executable'
        return 1
    }
    jq_path="$(_mainframe_resolve_executable_path "$jq_candidate")" || {
        _mainframe_enforce_bind_fail 'jq could not be safely resolved'
        return 1
    }
    [[ -f "$jq_path" && ! -L "$jq_path" && -x "$jq_path" ]] || {
        _mainframe_enforce_bind_fail 'jq is not a safe regular executable'
        return 1
    }
    if [[ "$project" == / || "$jq_path" == "$project" || "$jq_path" == "$project/"* ]]; then
        _mainframe_enforce_bind_fail 'refusing a project-controlled jq executable'
        return 1
    fi
    case "$jq_path" in
        /usr/bin/jq|/bin/jq|/usr/local/bin/jq|\
        /opt/homebrew/Cellar/*/bin/jq|/usr/local/Cellar/*/bin/jq|\
        /home/linuxbrew/.linuxbrew/Cellar/*/bin/jq|/nix/store/*/bin/jq) ;;
        *)
            _mainframe_enforce_bind_fail \
                'refusing jq outside a supported system or package-manager installation'
            return 1
            ;;
    esac
    [[ "$jq_path" != *$'\n'* && "$jq_path" != *$'\r'* &&
       "$jq_path" != *$'\t'* ]] || {
        _mainframe_enforce_bind_fail 'the jq path contains unsupported control characters'
        return 1
    }
    export MAINFRAME_AGENT_JQ="$jq_path"
}

_mainframe_enforce_jq() {
    [[ "${MAINFRAME_AGENT_JQ:-}" == /* && -f "$MAINFRAME_AGENT_JQ" &&
       ! -L "$MAINFRAME_AGENT_JQ" && -x "$MAINFRAME_AGENT_JQ" ]] || return 1
    "$MAINFRAME_AGENT_JQ" "$@"
}

_mainframe_enforce_bind_runtime() {
    local project="$1" search_path
    local bash_candidate bash_path jq_path gateway_path safety_path
    local bash_sha jq_sha gateway_sha safety_sha

    if (( $# >= 2 )); then
        search_path="$2"
    else
        search_path="${_MAINFRAME_AGENT_DISCOVERY_PATH-${PATH:-}}"
    fi

    _MAINFRAME_ENFORCE_BIND_ERROR=""
    unset MAINFRAME_AGENT_BASH MAINFRAME_AGENT_JQ MAINFRAME_AGENT_GATEWAY \
        MAINFRAME_AGENT_SAFETY MAINFRAME_AGENT_SEAL

    [[ -x /bin/bash ]] || {
        _mainframe_enforce_bind_fail '/bin/bash is required for the privileged hook bootstrap'
        return 1
    }
    /bin/bash -p -c ':' >/dev/null 2>&1 || {
        _mainframe_enforce_bind_fail '/bin/bash could not start the privileged hook bootstrap'
        return 1
    }

    # The public CLI has already selected/re-executed under a supported Bash.
    # Bind that exact interpreter rather than re-reading a mutable PATH entry.
    bash_candidate="${BASH:-}"
    [[ -n "$bash_candidate" ]] || {
        _mainframe_enforce_bind_fail 'the active Bash executable is unavailable'
        return 1
    }
    [[ "$bash_candidate" == /* ]] || bash_candidate="$(type -P "$bash_candidate" 2>/dev/null || true)"
    bash_path="$(_mainframe_resolve_executable_path "$bash_candidate")" || {
        _mainframe_enforce_bind_fail 'the active Bash executable could not be safely resolved'
        return 1
    }
    [[ -f "$bash_path" && ! -L "$bash_path" && -x "$bash_path" ]] || {
        _mainframe_enforce_bind_fail 'the active Bash path is not a safe executable'
        return 1
    }
    "$bash_path" --noprofile --norc -p -c '
        (( BASH_VERSINFO[0] > 4 )) ||
        (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
    ' >/dev/null 2>&1 || {
        _mainframe_enforce_bind_fail 'the gateway requires Bash 4.4 or newer'
        return 1
    }

    _mainframe_enforce_bind_jq "$project" "$search_path" || return 1
    jq_path="$MAINFRAME_AGENT_JQ"

    gateway_path="${MAINFRAME_ROOT:-}/hooks/agent-gateway.sh"
    safety_path="${MAINFRAME_ROOT:-}/lib/agent_safety.sh"
    [[ "$gateway_path" == /* && -f "$gateway_path" && ! -L "$gateway_path" &&
       -r "$gateway_path" ]] || {
        _mainframe_enforce_bind_fail 'the installed agent gateway is missing or unsafe'
        return 1
    }
    [[ "$safety_path" == /* && -f "$safety_path" && ! -L "$safety_path" &&
       -r "$safety_path" ]] || {
        _mainframe_enforce_bind_fail 'the installed agent safety policy is missing or unsafe'
        return 1
    }
    if [[ "$project" == / || "$bash_path" == "$project" || "$bash_path" == "$project/"* ||
          "$jq_path" == "$project" || "$jq_path" == "$project/"* ||
          "$gateway_path" == "$project" || "$gateway_path" == "$project/"* ||
          "$safety_path" == "$project" || "$safety_path" == "$project/"* ]]; then
        _mainframe_enforce_bind_fail 'refusing a project-controlled gateway dependency'
        return 1
    fi
    [[ "$bash_path" != *$'\n'* && "$bash_path" != *$'\r'* && "$bash_path" != *$'\t'* &&
       "$jq_path" != *$'\n'* && "$jq_path" != *$'\r'* && "$jq_path" != *$'\t'* &&
       "$gateway_path" != *$'\n'* && "$gateway_path" != *$'\r'* &&
       "$gateway_path" != *$'\t'* && "$safety_path" != *$'\n'* &&
       "$safety_path" != *$'\r'* && "$safety_path" != *$'\t'* ]] || {
        _mainframe_enforce_bind_fail 'gateway dependency paths contain unsupported control characters'
        return 1
    }

    bash_sha="$(_mainframe_enforce_sha256_file "$bash_path")" || {
        _mainframe_enforce_bind_fail 'could not seal the active Bash executable'
        return 1
    }
    jq_sha="$(_mainframe_enforce_sha256_file "$jq_path")" || {
        _mainframe_enforce_bind_fail 'could not seal the trusted jq executable'
        return 1
    }
    gateway_sha="$(_mainframe_enforce_sha256_file "$gateway_path")" || {
        _mainframe_enforce_bind_fail 'could not seal the installed agent gateway'
        return 1
    }
    safety_sha="$(_mainframe_enforce_sha256_file "$safety_path")" || {
        _mainframe_enforce_bind_fail 'could not seal the installed agent safety policy'
        return 1
    }

    export MAINFRAME_AGENT_BASH="$bash_path"
    export MAINFRAME_AGENT_JQ="$jq_path"
    export MAINFRAME_AGENT_GATEWAY="$gateway_path"
    export MAINFRAME_AGENT_SAFETY="$safety_path"
    export MAINFRAME_AGENT_SEAL="$bash_sha:$jq_sha:$gateway_sha:$safety_sha"
}

# Exercise the same privileged bootstrap that is committed into host config.
# stdin is passed through to the gateway; every nonzero child result is 2.
_mainframe_enforce_gateway_probe() {
    local format="$1"
    /bin/bash -p -c "$_MAINFRAME_AGENT_HOOK_BOOTSTRAP" \
        mainframe-agent-hook "$format"
}

_mainframe_enforce_require_jq() {
    if [[ "${MAINFRAME_AGENT_JQ:-}" != /* || ! -x "$MAINFRAME_AGENT_JQ" ]]; then
        echo "MAINFRAME enforcement requires a bound, non-project jq executable." >&2
        return 1
    fi
}

# Reject malformed or schema-incompatible host configuration before changing
# either instruction files or hook configuration. This keeps `activate all
# --enforce` from partially modifying a project because a later JSON file is
# invalid.
_mainframe_enforce_validate_file() {
    local host="$1" file="$2" event
    if [[ -L "$file" ]]; then
        echo "Refusing to modify symbolic-link enforcement config: $file" >&2
        return 1
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        echo "Enforcement config is not a regular file: $file" >&2
        return 1
    fi
    [[ -f "$file" ]] || return 0

    if ! _mainframe_enforce_jq -e -s 'length == 1 and (.[0] | type == "object")' "$file" >/dev/null 2>&1; then
        echo "Invalid JSON object in enforcement config: $file" >&2
        return 1
    fi

    case "$host" in
        codex|claude-code) event="PreToolUse" ;;
        gemini) event="BeforeTool" ;;
        copilot)
            if ! _mainframe_enforce_jq -e '
                (.version == 1) and
                ((has("hooks") | not) or
                    ((.hooks | type == "object") and
                     ((.hooks | has("preToolUse") | not) or
                      (.hooks.preToolUse | type == "array"))))
            ' "$file" >/dev/null 2>&1; then
                echo "Unsupported Copilot hook schema in: $file" >&2
                return 1
            fi
            return 0
            ;;
        *)
            echo "Unsupported enforcement host: $host" >&2
            return 1
            ;;
    esac

    if ! _mainframe_enforce_jq -e --arg event "$event" '
        ((has("hooks") | not) or
            ((.hooks | type == "object") and
             ((.hooks | has($event) | not) or
              (.hooks[$event] | type == "array"))))
    ' "$file" >/dev/null 2>&1; then
        echo "Unsupported $host hook schema in: $file" >&2
        return 1
    fi
}

_mainframe_enforce_preflight() {
    local project="$1"
    shift
    _mainframe_enforce_bind_jq "$project" || {
        echo "MAINFRAME enforcement runtime is not ready: ${_MAINFRAME_ENFORCE_BIND_ERROR:-jq binding failed}" >&2
        return 1
    }
    _mainframe_enforce_require_jq || return 1

    local host rel
    for host in "$@"; do
        _mainframe_enforce_supported "$host" || continue
        rel="$(_mainframe_enforce_file_for "$host")"
        _mainframe_activate_validate_managed_path "$project" "$rel" || return 1
        _mainframe_enforce_validate_file "$host" "$project/$rel" || return 1
    done
}

# Emit the desired host configuration on stdout. Claude and Gemini reuse an
# existing same-matcher group when possible, while deactivation removes only
# the exact MAINFRAME command object (or its otherwise-empty canonical group).
# shellcheck disable=SC2016 # $command/$hook are jq variables, not shell variables.
_mainframe_enforce_transform() {
    local host="$1" action="$2" file="$3" filter command input

    case "$host" in
        codex|claude-code)
            command="$(_mainframe_enforce_command_for "$host")" || return 1
            if [[ "$action" == "activate" ]]; then
                filter='
                    {type: "command", command: $command} as $hook
                    | {matcher: "Bash", hooks: [$hook]} as $entry
                    | .hooks = (.hooks // {})
                    | .hooks.PreToolUse = (.hooks.PreToolUse // [])
                    | if any(.hooks.PreToolUse[];
                        if type == "object" and .matcher == "Bash" and (.hooks | type == "array")
                        then any(.hooks[]; . == $hook)
                        else false
                        end)
                      then .
                      else
                        (.hooks.PreToolUse
                            | map(if type == "object"
                                  then (.matcher == "Bash" and (.hooks | type == "array"))
                                  else false
                                  end)
                            | index(true)) as $index
                        | if $index == null then .hooks.PreToolUse += [$entry]
                          else .hooks.PreToolUse[$index].hooks += [$hook]
                          end
                      end
                '
            else
                filter='
                    {type: "command", command: $command} as $hook
                    | {matcher: "Bash", hooks: [$hook]} as $entry
                    | .hooks = (.hooks // {})
                    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | map(
                        if . == $entry then empty
                        elif type == "object" and .matcher == "Bash" and (.hooks | type == "array")
                        then .hooks |= map(select(. != $hook))
                        else .
                        end
                      ))
                    | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
                    | if .hooks == {} then del(.hooks) else . end
                '
            fi
            ;;
        gemini)
            command="$(_mainframe_enforce_command_for "$host")" || return 1
            if [[ "$action" == "activate" ]]; then
                filter='
                    {type: "command", command: $command} as $hook
                    | {matcher: "run_shell_command", hooks: [$hook]} as $entry
                    | .hooks = (.hooks // {})
                    | .hooks.BeforeTool = (.hooks.BeforeTool // [])
                    | if any(.hooks.BeforeTool[];
                        if type == "object" and .matcher == "run_shell_command" and (.hooks | type == "array")
                        then any(.hooks[]; . == $hook)
                        else false
                        end)
                      then .
                      else
                        (.hooks.BeforeTool
                            | map(if type == "object"
                                  then (.matcher == "run_shell_command" and (.hooks | type == "array"))
                                  else false
                                  end)
                            | index(true)) as $index
                        | if $index == null then .hooks.BeforeTool += [$entry]
                          else .hooks.BeforeTool[$index].hooks += [$hook]
                          end
                      end
                '
            else
                filter='
                    {type: "command", command: $command} as $hook
                    | {matcher: "run_shell_command", hooks: [$hook]} as $entry
                    | .hooks = (.hooks // {})
                    | .hooks.BeforeTool = ((.hooks.BeforeTool // []) | map(
                        if . == $entry then empty
                        elif type == "object" and .matcher == "run_shell_command" and (.hooks | type == "array")
                        then .hooks |= map(select(. != $hook))
                        else .
                        end
                      ))
                    | if .hooks.BeforeTool == [] then del(.hooks.BeforeTool) else . end
                    | if .hooks == {} then del(.hooks) else . end
                '
            fi
            ;;
        copilot)
            command="$(_mainframe_enforce_command_for "$host")" || return 1
            if [[ "$action" == "activate" ]]; then
                filter='
                    {type: "command", matcher: "bash", bash: $command} as $entry
                    | .version = (.version // 1)
                    | .hooks = (.hooks // {})
                    | .hooks.preToolUse = (.hooks.preToolUse // [])
                    | if any(.hooks.preToolUse[]; . == $entry) then .
                      else .hooks.preToolUse += [$entry]
                      end
                '
            else
                filter='
                    {type: "command", matcher: "bash", bash: $command} as $entry
                    | .hooks = (.hooks // {})
                    | .hooks.preToolUse = ((.hooks.preToolUse // []) | map(select(. != $entry)))
                    | if .hooks.preToolUse == [] then del(.hooks.preToolUse) else . end
                    | if .hooks == {} then del(.hooks) else . end
                    | if . == {version: 1} then {} else . end
                '
            fi
            ;;
        *) return 1 ;;
    esac

    if [[ -f "$file" ]]; then
        input="$file"
        _mainframe_enforce_jq --arg command "$command" "$filter" "$input"
    else
        printf '{}\n' | _mainframe_enforce_jq --arg command "$command" "$filter"
    fi
}

_mainframe_enforce_atomic_write() {
    local file="$1" content="$2" dir tmp mode=""
    dir="$(dirname "$file")"
    mkdir -p "$dir" || return 1
    tmp=$(mktemp "$dir/.mainframe-enforce.XXXXXX") || return 1

    if [[ -f "$file" ]]; then
        if stat -f '%Lp' "$file" >/dev/null 2>&1; then
            mode=$(stat -f '%Lp' "$file")
        else
            mode=$(stat -c '%a' "$file" 2>/dev/null || true)
        fi
    fi
    if ! printf '%s\n' "$content" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    [[ -z "$mode" ]] || chmod "$mode" "$tmp"
    if ! mv "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

_mainframe_enforce_apply() {
    local host="$1" project="$2" dry_run="$3" rel file desired current_norm desired_norm existed=false
    rel="$(_mainframe_enforce_file_for "$host")"
    file="$project/$rel"
    [[ -f "$file" ]] && existed=true

    desired="$(_mainframe_enforce_transform "$host" activate "$file")" || {
        echo "error"
        return 1
    }
    desired_norm=$(printf '%s\n' "$desired" | _mainframe_enforce_jq -cS .) || return 1
    if [[ "$existed" == "true" ]]; then
        current_norm=$(_mainframe_enforce_jq -cS . "$file") || return 1
        if [[ "$current_norm" == "$desired_norm" ]]; then
            echo "enforcement-current"
            return 0
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        [[ "$existed" == "true" ]] && echo "would-enforce-update" || echo "would-enforce-create"
        return 0
    fi
    _mainframe_enforce_atomic_write "$file" "$desired" || {
        echo "error"
        return 1
    }
    [[ "$existed" == "true" ]] && echo "enforcement-updated" || echo "enforcement-created"
}

_mainframe_enforce_remove() {
    local host="$1" project="$2" dry_run="$3" rel file desired current_norm desired_norm
    rel="$(_mainframe_enforce_file_for "$host")"
    file="$project/$rel"
    if [[ ! -f "$file" ]]; then
        echo "enforcement-not-present"
        return 0
    fi

    desired="$(_mainframe_enforce_transform "$host" deactivate "$file")" || {
        echo "error"
        return 1
    }
    current_norm=$(_mainframe_enforce_jq -cS . "$file") || return 1
    desired_norm=$(printf '%s\n' "$desired" | _mainframe_enforce_jq -cS .) || return 1
    if [[ "$current_norm" == "$desired_norm" ]]; then
        echo "no-mainframe-enforcement"
        return 0
    fi
    if [[ "$dry_run" == "true" ]]; then
        echo "would-remove-enforcement"
        return 0
    fi

    # A settings file containing only MAINFRAME's canonical entry has no
    # remaining semantics after removal. Delete it; otherwise atomically write
    # the preserved user configuration.
    if printf '%s\n' "$desired" | _mainframe_enforce_jq -e 'type == "object" and length == 0' >/dev/null; then
        rm -f "$file"
    else
        _mainframe_enforce_atomic_write "$file" "$desired" || {
            echo "error"
            return 1
        }
    fi
    echo "enforcement-removed"
}

# Read the one canonical activation payload carried by the generated Codex
# adapter. The generator binds this payload and its conservative evidence
# boundary to the exact registry digest, so activation has no second Markdown
# instruction source to drift from the static host adapters.
_mainframe_activate_contract_record() {
    local source_file="${BASH_SOURCE[0]}" physical_lib physical_root
    local source_dir="${source_file%/*}"
    physical_lib="$(cd "$source_dir" && pwd -P)" || {
        echo "invalid activation contract: source root cannot be resolved" >&2
        return 1
    }
    physical_root="${physical_lib%/*}"
    local adapter="${physical_root}/skills/codex/AGENTS.md"
    local registry="${physical_root}/config/host-capabilities.json"
    local marker payload_line boundary registry_digest marker_digest block_version
    local payload_prefix='<!-- MAINFRAME-ACTIVATION-PAYLOAD '
    local payload_suffix=' -->'

    if [[ ! -f "$adapter" || -L "$adapter" || ! -f "$registry" || -L "$registry" ]]; then
        echo "invalid activation contract: canonical adapter or registry is missing or unsafe" >&2
        return 1
    fi
    if [[ "$(grep -c '^<!-- MAINFRAME-ACTIVATION-CONTRACT ' "$adapter")" -ne 1 ||
          "$(grep -c '^<!-- MAINFRAME-ACTIVATION-PAYLOAD ' "$adapter")" -ne 1 ]]; then
        echo "invalid activation contract: canonical markers are missing or duplicated" >&2
        return 1
    fi

    marker="$(grep '^<!-- MAINFRAME-ACTIVATION-CONTRACT ' "$adapter")" || return 1
    payload_line="$(grep '^<!-- MAINFRAME-ACTIVATION-PAYLOAD ' "$adapter")" || return 1
    boundary="$(grep '^> Instruction evidence: instructions only\.' "$adapter")" || {
        echo "invalid activation contract: conservative evidence boundary is missing" >&2
        return 1
    }
    [[ "$(grep -c '^> Instruction evidence: instructions only\.' "$adapter")" -eq 1 &&
       "$boundary" == *"unsupported routes remain unverified." ]] || {
        echo "invalid activation contract: conservative evidence boundary is ambiguous" >&2
        return 1
    }

    registry_digest="$(_mainframe_enforce_sha256_file "$registry")" || {
        echo "invalid activation contract: registry digest is unavailable" >&2
        return 1
    }
    marker_digest="$(printf '%s\n' "$marker" | sed -nE \
        's/^.*"registry_sha256":"([0-9a-f]{64})".*$/\1/p')"
    block_version="$(printf '%s\n' "$marker" | sed -nE \
        's/^.*"block_version":([1-9][0-9]*).*$/\1/p')"
    [[ "$marker_digest" == "$registry_digest" && "$block_version" == "1" &&
       "$marker" == '<!-- MAINFRAME-ACTIVATION-CONTRACT {"schema_version":1,"contract_version":"'* &&
       "$marker" == *'","registry":"config/host-capabilities.json","registry_sha256":"'* &&
       "$marker" == *'","block_version":1,"adapter_evidence_level":"instructions","unsupported_routes":"unverified"} -->' ]] || {
        echo "invalid activation contract: identity, version, or evidence boundary does not match the registry" >&2
        return 1
    }

    [[ "$payload_line" == "$payload_prefix"*"$payload_suffix" ]] || {
        echo "invalid activation contract: payload marker is malformed" >&2
        return 1
    }
    payload_line="${payload_line#"$payload_prefix"}"
    payload_line="${payload_line%"$payload_suffix"}"
    [[ -n "$payload_line" && "$payload_line" != *[!A-Za-z0-9+/=]* ]] || {
        echo "invalid activation contract: payload encoding is malformed" >&2
        return 1
    }

    printf '%s\n%s\n%s\n%s\n' "$block_version" "$marker" "$boundary" "$payload_line"
}

_mainframe_activate_decode_payload() {
    local encoded="$1"
    if [[ -x /usr/bin/base64 ]]; then
        if [[ "$(/usr/bin/uname -s 2>/dev/null)" == Darwin ]]; then
            printf '%s' "$encoded" | /usr/bin/base64 -D
        else
            printf '%s' "$encoded" | /usr/bin/base64 --decode
        fi
    elif [[ -x /bin/base64 ]]; then
        printf '%s' "$encoded" | /bin/base64 --decode
    else
        echo "invalid activation contract: base64 decoder is unavailable" >&2
        return 1
    fi
}

_mainframe_activate_block_version() {
    local record
    record="$(_mainframe_activate_contract_record)" || return 1
    printf '%s\n' "${record%%$'\n'*}"
}

_mainframe_activate_block() {
    local record payload
    local -a fields=()
    record="$(_mainframe_activate_contract_record)" || return 1
    mapfile -t fields <<< "$record"
    [[ "${#fields[@]}" -eq 4 ]] || {
        echo "invalid activation contract: canonical record is malformed" >&2
        return 1
    }
    payload="$(_mainframe_activate_decode_payload "${fields[3]}")" || {
        echo "invalid activation contract: payload cannot be decoded" >&2
        return 1
    }
    [[ "$payload" == '## MAINFRAME (AI-native bash runtime)'$'\n'* &&
       "$payload" == *'MAINFRAME is a validation layer, not a sandbox'* ]] || {
        echo "invalid activation contract: decoded instructions are not canonical" >&2
        return 1
    }

    printf '<!-- %s:BEGIN v%s -->\n%s\n%s\n\n%s\n<!-- %s:END v%s -->\n' \
        "$_MAINFRAME_ACTIVATE_MARKER_TAG" "${fields[0]}" "${fields[1]}" \
        "${fields[2]}" "$payload" "$_MAINFRAME_ACTIVATE_MARKER_TAG" "${fields[0]}"
}

# _mainframe_activate_apply <file> <dry-run> ; prints result status on stdout
_mainframe_activate_apply() {
    local file="$1" dry_run="$2"
    local block_version begin end block
    block_version="$(_mainframe_activate_block_version)" || return 1
    begin="<!-- ${_MAINFRAME_ACTIVATE_MARKER_TAG}:BEGIN v${block_version} -->"
    end="<!-- ${_MAINFRAME_ACTIVATE_MARKER_TAG}:END v${block_version} -->"
    block="$(_mainframe_activate_block)" || return 1

    if [[ -f "$file" ]] && grep -qF "$begin" "$file" && grep -qF "$end" "$file"; then
        # Update in place: replace content between markers (inclusive)
        local current
        current=$(sed -n "/<!-- ${_MAINFRAME_ACTIVATE_MARKER_TAG}:BEGIN/,/<!-- ${_MAINFRAME_ACTIVATE_MARKER_TAG}:END/p" "$file")
        if [[ "$current" == "$block" ]]; then
            echo "already-current"
            return 0
        fi
        if [[ "$dry_run" == "true" ]]; then
            echo "would-update"
            return 0
        fi
        local tmp blockfile
        tmp=$(mktemp "${TMPDIR:-/tmp}/mainframe-activate.XXXXXX")
        blockfile=$(mktemp "${TMPDIR:-/tmp}/mainframe-activate-block.XXXXXX")
        printf '%s\n' "$block" > "$blockfile"
        # Replace the marked region with the block (BSD awk cannot take
        # multiline -v strings, so the block is read from a file).
        if awk -v tag="$_MAINFRAME_ACTIVATE_MARKER_TAG" -v blockfile="$blockfile" '
            $0 ~ "<!-- " tag ":BEGIN" { system("cat \"" blockfile "\""); skip=1; next }
            $0 ~ "<!-- " tag ":END" { skip=0; next }
            !skip { print }
        ' "$file" > "$tmp"; then
            mv "$tmp" "$file"
            rm -f "$blockfile"
            echo "updated"
        else
            rm -f "$tmp" "$blockfile"
            echo "error"
            return 1
        fi
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        [[ -f "$file" ]] && echo "would-append" || echo "would-create"
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    if [[ -f "$file" ]]; then
        # Never overwrite: append the managed block with a separating blank line
        { printf '\n\n%s\n' "$block"; } >> "$file"
        echo "appended"
    else
        { printf '# Project agent instructions\n\n%s\n' "$block"; } > "$file"
        echo "created"
    fi
}

# _mainframe_activate_remove <file> <dry-run>
_mainframe_activate_remove() {
    local file="$1" dry_run="$2"
    local tag="$_MAINFRAME_ACTIVATE_MARKER_TAG"

    if [[ ! -f "$file" ]]; then
        echo "not-present"
        return 0
    fi
    if ! grep -qF "<!-- ${tag}:BEGIN" "$file"; then
        echo "no-managed-content"
        return 0
    fi
    if [[ "$dry_run" == "true" ]]; then
        echo "would-remove"
        return 0
    fi
    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/mainframe-deactivate.XXXXXX")
    awk -v tag="$tag" '
        $0 ~ "<!-- " tag ":BEGIN" { skip=1; next }
        $0 ~ "<!-- " tag ":END" { skip=0; next }
        !skip { print }
    ' "$file" > "$tmp"
    # Collapse 3+ consecutive blank lines left by removal
    awk 'BEGIN{blank=0} /^[[:space:]]*$/{blank++; if(blank<=2) print; next} {blank=0; print}' "$tmp" > "$tmp.2"
    mv "$tmp.2" "$file"
    rm -f "$tmp"
    echo "removed"
}

mainframe_activate() {
    local host="" project="." dry_run=false enforce=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -ge 2 ]] || { echo "--project requires a directory" >&2; return 1; }
                project="$2"; shift 2
                ;;
            --dry-run) dry_run=true; shift ;;
            --enforce) enforce=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: mainframe activate <host|all> --project <dir> [--dry-run] [--enforce]
       mainframe activate status
       mainframe deactivate <host|all> --project <dir> [--dry-run] [--enforce]

Hosts: codex, claude-code, copilot, gemini, cursor, jetbrains, junie (or 'all')

Merge-safe: activation writes a marked MAINFRAME block into the host's
instruction file; it never overwrites existing content, and deactivation
removes only the marked block.

--enforce also installs a blocking pre-tool shell hook for Codex, Claude Code,
Copilot, and Gemini. Enforcement requires jq and is never enabled implicitly.
EOF
                return 0 ;;
            *) host="$1"; shift ;;
        esac
    done

    if [[ "$host" == "status" || -z "$host" && "$0" == *status* ]]; then
        if [[ "$enforce" == "true" ]]; then
            echo "--enforce is not supported with activate status" >&2
            return 1
        fi
        mainframe_activate_status --project "$project"
        return $?
    fi
    [[ -n "$host" ]] || { echo "Usage: mainframe activate <host|all> --project <dir> [--dry-run] [--enforce]" >&2; return 1; }

    local hosts=()
    if [[ "$host" == "all" ]]; then
        while IFS= read -r h; do hosts+=("$h"); done < <(_mainframe_activate_known_hosts)
    else
        if ! _mainframe_activate_file_for "$host" >/dev/null; then
            echo "Unknown host: $host (known: $(_mainframe_activate_known_hosts | tr '\n' ' ')all)" >&2
            return 1
        fi
        hosts=("$host")
    fi

    project="$(_mainframe_activate_project_root "$project")" || return 1
    _mainframe_activate_paths_preflight "$project" "$enforce" "${hosts[@]}" || return 1

    if [[ "$enforce" == "true" ]]; then
        if [[ "$host" != "all" ]] && ! _mainframe_enforce_supported "$host"; then
            echo "Enforcement is not supported for $host (supported: codex, claude-code, copilot, gemini)" >&2
            return 1
        fi
        if ! _mainframe_enforce_bind_runtime "$project"; then
            echo "MAINFRAME enforcement runtime is not ready: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}" >&2
            return 1
        fi
        _mainframe_enforce_preflight "$project" "${hosts[@]}" || return 1
    fi

    local rc=0 h rel result
    for h in "${hosts[@]}"; do
        rel="$(_mainframe_activate_file_for "$h")"
        result="$(_mainframe_activate_apply "$project/$rel" "$dry_run")" || rc=1
        printf '%-12s %-38s %s\n' "$h" "$rel" "$result"
    done

    if [[ "$enforce" == "true" && "$rc" -eq 0 ]]; then
        for h in "${hosts[@]}"; do
            _mainframe_enforce_supported "$h" || continue
            rel="$(_mainframe_enforce_file_for "$h")"
            result="$(_mainframe_enforce_apply "$h" "$project" "$dry_run")" || rc=1
            printf '%-12s %-38s %s\n' "$h" "$rel" "$result"
        done
    fi
    return $rc
}

mainframe_deactivate() {
    local host="" project="." dry_run=false enforce=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -ge 2 ]] || { echo "--project requires a directory" >&2; return 1; }
                project="$2"; shift 2
                ;;
            --dry-run) dry_run=true; shift ;;
            --enforce) enforce=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: mainframe deactivate <host|all> --project <dir> [--dry-run] [--enforce]

--enforce removes only MAINFRAME's exact pre-tool hook entry for Codex,
Claude Code, Copilot, or Gemini; all other host configuration is retained.
EOF
                return 0
                ;;
            *) host="$1"; shift ;;
        esac
    done
    [[ -n "$host" ]] || { echo "Usage: mainframe deactivate <host|all> --project <dir> [--dry-run] [--enforce]" >&2; return 1; }

    local hosts=()
    if [[ "$host" == "all" ]]; then
        while IFS= read -r h; do hosts+=("$h"); done < <(_mainframe_activate_known_hosts)
    else
        _mainframe_activate_file_for "$host" >/dev/null || { echo "Unknown host: $host" >&2; return 1; }
        hosts=("$host")
    fi

    project="$(_mainframe_activate_project_root "$project")" || return 1
    _mainframe_activate_paths_preflight "$project" "$enforce" "${hosts[@]}" || return 1

    if [[ "$enforce" == "true" ]]; then
        if [[ "$host" != "all" ]] && ! _mainframe_enforce_supported "$host"; then
            echo "Enforcement is not supported for $host (supported: codex, claude-code, copilot, gemini)" >&2
            return 1
        fi
        _mainframe_enforce_preflight "$project" "${hosts[@]}" || return 1
    fi

    local rc=0 h rel result
    for h in "${hosts[@]}"; do
        rel="$(_mainframe_activate_file_for "$h")"
        result="$(_mainframe_activate_remove "$project/$rel" "$dry_run")" || rc=1
        printf '%-12s %-38s %s\n' "$h" "$rel" "$result"
    done

    if [[ "$enforce" == "true" ]]; then
        for h in "${hosts[@]}"; do
            _mainframe_enforce_supported "$h" || continue
            rel="$(_mainframe_enforce_file_for "$h")"
            result="$(_mainframe_enforce_remove "$h" "$project" "$dry_run")" || rc=1
            printf '%-12s %-38s %s\n' "$h" "$rel" "$result"
        done
    fi
    return $rc
}

mainframe_activate_status() {
    local project="."
    while [[ $# -gt 0 ]]; do
        case "$1" in --project) project="$2"; shift 2 ;; *) shift ;; esac
    done

    project="$(_mainframe_activate_project_root "$project")" || return 1

    local tag="$_MAINFRAME_ACTIVATE_MARKER_TAG" h rel file state validation
    printf '%-12s %-38s %s\n' "HOST" "FILE" "STATE"
    while IFS= read -r h; do
        rel="$(_mainframe_activate_file_for "$h")"
        file="$project/$rel"
        if ! validation="$(_mainframe_activate_validate_managed_path "$project" "$rel" 2>&1)"; then
            state="invalid (${validation//$'\n'/; })"
        elif [[ ! -f "$file" ]]; then
            state="not-activated"
        elif grep -qF "<!-- ${tag}:BEGIN" "$file"; then
            local current
            current=$(sed -n "/<!-- ${tag}:BEGIN/,/<!-- ${tag}:END/p" "$file")
            [[ "$current" == "$(_mainframe_activate_block)" ]] \
                && state="active (current)" || state="active (stale block)"
        else
            state="file-exists (no MAINFRAME block)"
        fi
        printf '%-12s %-38s %s\n' "$h" "$rel" "$state"
    done < <(_mainframe_activate_known_hosts)
}

# Return the number of exact MAINFRAME enforcement entries in a validated
# host configuration. Status deliberately checks the exact object generated by
# activation; a similar-looking or weakened foreign command is not protection.
_mainframe_enforce_entry_count() {
    local host="$1" file="$2" command
    command="$(_mainframe_enforce_command_for "$host")" || return 1

    case "$host" in
        codex|claude-code)
            _mainframe_enforce_jq -r --arg command "$command" '
                [.hooks.PreToolUse[]?
                  | select(type == "object" and .matcher == "Bash" and (.hooks | type == "array"))
                  | .hooks[]
                  | select(. == {type: "command", command: $command})
                ] | length
            ' "$file"
            ;;
        gemini)
            _mainframe_enforce_jq -r --arg command "$command" '
                [.hooks.BeforeTool[]?
                  | select(type == "object" and .matcher == "run_shell_command" and (.hooks | type == "array"))
                  | .hooks[]
                  | select(. == {type: "command", command: $command})
                ] | length
            ' "$file"
            ;;
        copilot)
            _mainframe_enforce_jq -r --arg command "$command" '
                [.hooks.preToolUse[]?
                  | select(. == {
                      type: "command",
                      matcher: "bash",
                      bash: $command
                    })
                ] | length
            ' "$file"
            ;;
        *) return 1 ;;
    esac
}

# Emit a tab-separated state/detail record for one enforcement host.
_mainframe_protect_config_record() {
    local host="$1" project="$2" rel file validation count detail
    rel="$(_mainframe_enforce_file_for "$host")" || return 1
    file="$project/$rel"

    if ! validation="$(_mainframe_activate_validate_managed_path "$project" "$rel" 2>&1)"; then
        validation="${validation//$'\n'/; }"
        printf 'invalid\t%s\n' "$validation"
        return 0
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        printf 'invalid\tconfig is not a regular file\n'
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        printf 'missing\tconfig file is absent\n'
        return 0
    fi
    if [[ "${MAINFRAME_AGENT_JQ:-}" != /* || ! -x "$MAINFRAME_AGENT_JQ" ]]; then
        printf 'invalid\tcannot inspect config because jq is unavailable\n'
        return 0
    fi
    if ! validation="$(_mainframe_enforce_validate_file "$host" "$file" 2>&1)"; then
        validation="${validation//$'\n'/; }"
        printf 'invalid\t%s\n' "$validation"
        return 0
    fi
    if ! count="$(_mainframe_enforce_entry_count "$host" "$file" 2>/dev/null)" ||
       [[ ! "$count" =~ ^[0-9]+$ ]]; then
        printf 'invalid\tunable to inspect exact MAINFRAME hook entry\n'
        return 0
    fi
    if (( count == 0 )); then
        printf 'missing\texact MAINFRAME hook entry is absent; foreign config retained\n'
        return 0
    fi

    detail="exact MAINFRAME hook entry present"
    if (( count > 1 )); then
        detail+=" ($count duplicates)"
    fi
    if [[ "$host" == "codex" ]]; then
        detail+="; Codex trust and runtime load unverified"
    fi
    printf 'configured\t%s\n' "$detail"
}

_mainframe_bash_44_or_newer() {
    local major="${1:-${BASH_VERSINFO[0]}}"
    local minor="${2:-${BASH_VERSINFO[1]}}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    (( major > 4 || (major == 4 && minor >= 4) ))
}

# Resolve symlinks without GNU readlink -f so the same check works on macOS
# and Linux. A bare shell function/alias is intentionally not accepted: host
# hooks need a durable executable on PATH.
_mainframe_resolve_executable_path() {
    local source="$1" dir target links=0
    [[ "$source" == */* ]] || return 1
    [[ "$source" == /* ]] || source="$PWD/$source"

    while [[ -L "$source" ]]; do
        (( links < 40 )) || return 1
        links=$((links + 1))
        dir="${source%/*}"
        [[ -n "$dir" ]] || dir=/
        dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
        if [[ -x /usr/bin/readlink ]]; then
            target="$(/usr/bin/readlink "$source")" || return 1
        elif [[ -x /bin/readlink ]]; then
            target="$(/bin/readlink "$source")" || return 1
        else
            return 1
        fi
        [[ "$target" == /* ]] && source="$target" || source="$dir/$target"
    done
    dir="${source%/*}"
    [[ -n "$dir" ]] || dir=/
    dir="$(cd -- "$dir" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "${dir%/}" "${source##*/}"
}

_mainframe_protect_status() {
    local project="." requested="all" requested_set=false
    local h rel state detail mode issues=0
    local runtime_bindings_state runtime_bindings_detail

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                [[ $# -ge 2 ]] || { echo "--project requires a directory" >&2; return 1; }
                project="$2"
                shift 2
                ;;
            --host)
                [[ $# -ge 2 ]] || { echo "--host requires a host name" >&2; return 1; }
                requested="$2"
                requested_set=true
                shift 2
                ;;
            -h|--help)
                cat <<'EOF'
Usage: mainframe protect status [host|all] --project <dir>

Checks static, project-scoped enforcement readiness without changing files.
Configured-on-disk does not prove that a running host trusted or loaded a hook.
EOF
                return 0
                ;;
            --*)
                echo "Unknown protect status option: $1" >&2
                return 1
                ;;
            *)
                if [[ "$requested_set" == "true" ]]; then
                    echo "Only one host may be requested" >&2
                    return 1
                fi
                requested="$1"
                requested_set=true
                shift
                ;;
        esac
    done

    if [[ "$requested" != "all" ]] && ! _mainframe_activate_file_for "$requested" >/dev/null 2>&1; then
        echo "Unknown host: $requested (known: $(_mainframe_activate_known_hosts | tr '\n' ' ')all)" >&2
        return 1
    fi
    if [[ ! -d "$project" ]]; then
        echo "Project directory not found: $project" >&2
        return 1
    fi
    project="$(cd "$project" && pwd -P)" || return 1

    printf 'MAINFRAME Protection Status\n'
    printf 'Project: %s\n\n' "$project"
    printf '%-18s %-11s %s\n' "DEPENDENCY" "STATE" "DETAIL"

    if _mainframe_enforce_bind_runtime "$project"; then
        runtime_bindings_state="ready"
        runtime_bindings_detail="privileged /bin/bash bootstrap"
        printf '%-18s %-11s %s\n' "hook-bootstrap" "ready" "/bin/bash -p"
        printf '%-18s %-11s %s\n' "gateway-bash" "ready" "$MAINFRAME_AGENT_BASH"
        printf '%-18s %-11s %s\n' "jq" "ready" "$MAINFRAME_AGENT_JQ"
        printf '%-18s %-11s %s\n' "agent-gateway" "ready" "$MAINFRAME_AGENT_GATEWAY"
        printf '%-18s %-11s %s\n' "agent-policy" "ready" "$MAINFRAME_AGENT_SAFETY"
        printf '%-18s %-11s %s\n' "runtime-seal" "ready" "four SHA-256 identities"
    else
        runtime_bindings_state="not-ready"
        runtime_bindings_detail="${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown binding error}"
        printf '%-18s %-11s %s\n' "gateway-bindings" "$runtime_bindings_state" "$runtime_bindings_detail"
        ((issues += 1))
    fi

    printf '\n%-12s %-18s %-30s %-12s %s\n' "HOST" "MODE" "CONFIG" "STATE" "DETAIL"
    while IFS= read -r h; do
        [[ "$requested" == "all" || "$requested" == "$h" ]] || continue
        if _mainframe_enforce_supported "$h"; then
            mode="enforced-hook"
            rel="$(_mainframe_enforce_file_for "$h")"
            IFS=$'\t' read -r state detail < <(_mainframe_protect_config_record "$h" "$project")
            [[ "$state" == "configured" ]] || ((issues += 1))
        else
            mode="instruction-only"
            rel="$(_mainframe_activate_file_for "$h")"
            state="instruction-only"
            detail="no supported blocking pre-tool adapter"
            [[ "$requested" == "all" ]] || ((issues += 1))
        fi
        printf '%-12s %-18s %-30s %-12s %s\n' "$h" "$mode" "$rel" "$state" "$detail"
    done < <(_mainframe_activate_known_hosts)

    printf '\nRuntime load: UNVERIFIED (restart the host, inspect its hook UI, and run a disposable canary)\n'
    if (( issues == 0 )); then
        printf 'Static readiness: READY\n'
        return 0
    fi
    printf 'Static readiness: NOT READY (%d issue(s))\n' "$issues"
    return 1
}

_mainframe_protect_command() {
    local action="${1:-}"
    case "$action" in
        status)
            shift
            _mainframe_protect_status "$@"
            ;;
        -h|--help|help|"")
            cat <<'EOF'
Usage: mainframe protect status [host|all] --project <dir>

Reports exact host-hook configuration and local executable dependencies.
The command is read-only and exits nonzero when requested static enforcement
is not ready. Runtime hook trust/load still requires host-native verification.
EOF
            ;;
        *)
            echo "Unknown protect command: $action" >&2
            echo "Usage: mainframe protect status [host|all] --project <dir>" >&2
            return 1
            ;;
    esac
}

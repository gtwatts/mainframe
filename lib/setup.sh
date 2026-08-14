#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/setup.sh - Guided, discovery-first coding-agent setup
# =============================================================================
# Without an explicit --host this command is strictly read-only. It reports the
# local shell, project-hook host signals, and Pi's separate user-package state,
# then prints exact next commands. Project-hook hosts delegate to onboarding;
# Pi delegates only to its dedicated package manager with explicit intent.
# =============================================================================

[[ -n "${_MAINFRAME_SETUP_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_SETUP_LOADED=1

_mainframe_setup_usage() {
    cat <<'EOF'
Usage: mainframe setup --project <dir> [--proof] [--host <host>] [--runtime <source>] [--dry-run] [--yes]

Project-hook hosts: codex, claude-code, copilot, gemini
Pi uses a separate user-package flow: --host pi

Without --host, setup is strictly read-only. It reports Bash/zsh availability,
supported host CLI and project-marker signals, static protection, existing
project AWM state, and Pi CLI/package state. It never auto-selects a host or
changes files or state.

--proof adds a concise, zero-residue first-run mechanism proof. It checks
installation health, one fixed reviewed pure invocation, an isolated AWM
checkpoint retrieved by a fresh Bash process, and one classifier-only denial
without executing the canary. It never starts a coding host or Pi and removes
its private temporary AWM and broker state before reporting success.

Options:
  --project DIR     Existing project directory to inspect or configure (required)
  --proof           Run the hostless zero-residue first-run mechanism proof
  --host HOST       Select one project-hook host, or Pi's package flow
  --runtime SOURCE  auto (default), managed, or system project-host resolution
  --dry-run         Preview the selected host/package flow without writing
  --yes             Approve the selected flow on this command invocation
  -h, --help        Show this help
EOF
}

_mainframe_setup_proof_cleanup() {
    local proof_base="$1" proof_dir="$2" find_bin rm_bin rmdir_bin path

    [[ -n "$proof_base" && -n "$proof_dir" &&
       "$proof_dir" == "$proof_base"/mainframe-setup-proof.* &&
       -d "$proof_dir" && ! -L "$proof_dir" && -O "$proof_dir" ]] || return 1

    if [[ -x /usr/bin/find ]]; then
        find_bin=/usr/bin/find
    elif [[ -x /bin/find ]]; then
        find_bin=/bin/find
    else
        return 1
    fi
    if [[ -x /bin/rm ]]; then
        rm_bin=/bin/rm
    elif [[ -x /usr/bin/rm ]]; then
        rm_bin=/usr/bin/rm
    else
        return 1
    fi
    if [[ -x /bin/rmdir ]]; then
        rmdir_bin=/bin/rmdir
    elif [[ -x /usr/bin/rmdir ]]; then
        rmdir_bin=/usr/bin/rmdir
    else
        return 1
    fi

    # Walk the validated private root without following links. Remove only
    # owned regular files, links themselves, and owned directories. A special
    # file or an entry that escapes the root makes cleanup fail closed.
    while IFS= read -r -d '' path; do
        [[ "$path" == "$proof_dir"/* ]] || return 1
        if [[ -L "$path" ]]; then
            "$rm_bin" -f -- "$path" || return 1
        elif [[ -f "$path" ]]; then
            [[ -O "$path" ]] || return 1
            "$rm_bin" -f -- "$path" || return 1
        elif [[ -d "$path" ]]; then
            [[ -O "$path" ]] || return 1
            "$rmdir_bin" -- "$path" || return 1
        else
            return 1
        fi
    done < <("$find_bin" -P "$proof_dir" -depth -mindepth 1 -print0)
    "$rmdir_bin" -- "$proof_dir"
}

_mainframe_setup_proof_path_mode() {
    local path="$1" stat_bin mode

    if [[ -x /usr/bin/stat ]]; then
        stat_bin=/usr/bin/stat
    elif [[ -x /bin/stat ]]; then
        stat_bin=/bin/stat
    else
        return 1
    fi
    if mode="$("$stat_bin" -f '%Lp' "$path" 2>/dev/null)" &&
       [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
        printf '%s\n' "${mode#0}"
        return 0
    fi
    mode="$("$stat_bin" -c '%a' "$path" 2>/dev/null)" || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    printf '%s\n' "${mode#0}"
}

_mainframe_setup_proof_nonce() {
    local od_bin tr_bin nonce

    [[ -r /dev/urandom ]] || return 1
    if [[ -x /usr/bin/od ]]; then
        od_bin=/usr/bin/od
    elif [[ -x /bin/od ]]; then
        od_bin=/bin/od
    else
        return 1
    fi
    if [[ -x /usr/bin/tr ]]; then
        tr_bin=/usr/bin/tr
    elif [[ -x /bin/tr ]]; then
        tr_bin=/bin/tr
    else
        return 1
    fi
    nonce="$(LC_ALL=C "$od_bin" -An -tx1 -N16 /dev/urandom 2>/dev/null |
        "$tr_bin" -d ' \n')" || return 1
    [[ "$nonce" =~ ^[0-9a-f]{32}$ ]] || return 1
    printf '%s' "$nonce"
}

_mainframe_setup_proof_awm_exec() {
    local env_bin="$1" bash_bin="$2" cli="$3" proof_dir="$4" project="$5"
    shift 5

    "$env_bin" -i \
        HOME="$proof_dir/home" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        TMPDIR="$proof_dir/tmp" \
        XDG_CONFIG_HOME="$proof_dir/config" \
        XDG_STATE_HOME="$proof_dir/state" \
        AWM_ROOT="$proof_dir/awm" \
        AWM_BACKEND=file \
        AWM_COMPAT_WARNINGS=0 \
        MAINFRAME_AGENT_NAME=mainframe-first-run-proof \
        MAINFRAME_BASH="$bash_bin" \
        MAINFRAME_CONFIG="$proof_dir/config/mainframe.conf" \
        MAINFRAME_QUIET=1 \
        MAINFRAME_ROOT="$MAINFRAME_ROOT" \
        LC_ALL=C \
        "$bash_bin" --noprofile --norc -p "$cli" awm project "$@" \
            --project "$project"
}

_mainframe_setup_proof_awm_retrieve() {
    local env_bin="$1" bash_bin="$2" cli="$3" proof_dir="$4" project="$5"

    # This helper deliberately has no nonce argument or nonce environment.
    # The fresh protected Bash receives only the fixed lookup key and isolated
    # state paths; its result is compared with the nonce by the parent process.
    _mainframe_setup_proof_awm_exec \
        "$env_bin" "$bash_bin" "$cli" "$proof_dir" "$project" \
        get mainframe-first-run-continuity
}

_mainframe_setup_proof_host_summary() {
    local project="$1" discovery_path="$2"
    local host host_cli_name host_cli resolved marker first_host=""
    local -a detected_hosts=()

    while IFS= read -r host; do
        host_cli_name="$(_mainframe_setup_host_cli_name "$host")"
        host_cli="$(_mainframe_setup_executable_path \
            "$host_cli_name" "$discovery_path" || true)"
        if [[ -n "$host_cli" ]]; then
            resolved="$(_mainframe_launch_resolve_executable "$host_cli" || true)"
            if [[ -n "$resolved" && "$resolved" != "$project" &&
                  "$resolved" != "$project/"* ]]; then
                detected_hosts+=("$host")
                continue
            fi
        fi
        marker="$(_mainframe_setup_marker_summary "$host" "$project")"
        [[ "$marker" == none ]] || detected_hosts+=("$host")
    done < <(_mainframe_setup_hosts)

    if (( ${#detected_hosts[@]} == 0 )); then
        printf 'Host candidates:    none detected (no host was selected)\n'
        _MAINFRAME_SETUP_PROOF_HOST_ACTION=""
        return 0
    fi

    first_host="${detected_hosts[0]}"
    printf 'Host candidates:'
    printf ' %s' "${detected_hosts[@]}"
    printf '\n'
    printf -v _MAINFRAME_SETUP_PROOF_HOST_ACTION \
        'mainframe host status %q --runtime auto' "$first_host"
}

_mainframe_setup_proof_pi_summary() {
    local project="$1" discovery_path="$2"
    local pi_cli resolved cli_state='missing' package_state='inspection-failed'
    local agent_dir status_text pi_actionable=false

    pi_cli="$(_mainframe_setup_executable_path pi "$discovery_path" || true)"
    if [[ -n "$pi_cli" ]]; then
        resolved="$(_mainframe_launch_resolve_executable "$pi_cli" || true)"
        if [[ -z "$resolved" ]]; then
            cli_state='unsafe'
        elif [[ "$resolved" == "$project" || "$resolved" == "$project/"* ]]; then
            cli_state='repo-controlled'
        else
            cli_state='found'
            pi_actionable=true
        fi
    fi

    if _mainframe_setup_pi_load_manager; then
        agent_dir="$(_mainframe_pi_agent_dir 2>/dev/null || true)"
        if [[ -n "$agent_dir" && ! -e "$agent_dir" && ! -L "$agent_dir" ]]; then
            package_state='not-initialized'
        elif status_text="$(
            builtin cd -- "$project" 2>/dev/null && mainframe_pi_status 2>/dev/null
        )"; then
            package_state="$(_mainframe_setup_kv_value \
                "$status_text" state 2>/dev/null || printf 'inspection-failed')"
        fi
    else
        package_state='manager-unavailable'
    fi

    printf 'Pi package:         %s (CLI %s; not executed)\n' \
        "$package_state" "$cli_state"
    _MAINFRAME_SETUP_PROOF_PI_STATE="$package_state"
    _MAINFRAME_SETUP_PROOF_PI_ACTION=""
    if [[ "$pi_actionable" == true ]]; then
        case "$package_state" in
            ready)
                _MAINFRAME_SETUP_PROOF_PI_ACTION='/mainframe doctor'
                ;;
            not-installed|legacy|duplicate|upgrade-needed|collision|noncanonical|inactive)
                _MAINFRAME_SETUP_PROOF_PI_ACTION='mainframe pi install --dry-run'
                ;;
            *)
                _MAINFRAME_SETUP_PROOF_PI_ACTION='mainframe pi doctor'
                ;;
        esac
    fi
}

_mainframe_setup_proof() (
    local project="$1" discovery_path="$2"
    local cli proof_base proof_dir="" mktemp_bin mkdir_bin env_bin
    local broker_output classification nonce retrieved retrieval_status
    local private_path private_mode
    local next_action=""

    umask 077

    cli="$(_mainframe_onboard_cli)" || {
        _mainframe_setup_error 'the installed MAINFRAME CLI could not be resolved'
        return 1
    }

    printf 'MAINFRAME First-Run Proof\n'
    printf 'Project: %s\n' "$project"
    printf 'Mode: zero-residue mechanism proof\n\n'

    if ! "$cli" doctor >/dev/null 2>&1; then
        _mainframe_setup_error 'installation health proof failed; run mainframe doctor'
        return 1
    fi
    printf 'Install health:     PASS\n'

    proof_base="$(builtin cd -- /tmp 2>/dev/null && builtin pwd -P)" || {
        _mainframe_setup_error 'could not resolve the fixed temporary directory'
        return 1
    }
    if [[ -x /usr/bin/mktemp ]]; then
        mktemp_bin=/usr/bin/mktemp
    elif [[ -x /bin/mktemp ]]; then
        mktemp_bin=/bin/mktemp
    else
        _mainframe_setup_error 'a fixed-location mktemp is required for the proof audit'
        return 1
    fi
    if [[ -x /bin/mkdir ]]; then
        mkdir_bin=/bin/mkdir
    elif [[ -x /usr/bin/mkdir ]]; then
        mkdir_bin=/usr/bin/mkdir
    else
        _mainframe_setup_error 'a fixed-location mkdir is required for the proof state'
        return 1
    fi
    if [[ -x /usr/bin/env ]]; then
        env_bin=/usr/bin/env
    elif [[ -x /bin/env ]]; then
        env_bin=/bin/env
    else
        _mainframe_setup_error 'a fixed-location env is required for the fresh-process proof'
        return 1
    fi
    proof_dir="$($mktemp_bin -d "$proof_base/mainframe-setup-proof.XXXXXX")" || {
        _mainframe_setup_error 'could not create the private temporary proof directory'
        return 1
    }
    trap '_mainframe_setup_proof_cleanup "$proof_base" "$proof_dir" >/dev/null 2>&1 || true' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    /bin/chmod 700 "$proof_dir" 2>/dev/null || {
        _mainframe_setup_error 'could not secure the temporary proof directory'
        return 1
    }
    "$mkdir_bin" -p -- \
        "$proof_dir/home" \
        "$proof_dir/tmp" \
        "$proof_dir/config" \
        "$proof_dir/state" || {
        _mainframe_setup_error 'could not create isolated temporary proof state'
        return 1
    }
    /bin/chmod 700 \
        "$proof_dir/home" \
        "$proof_dir/tmp" \
        "$proof_dir/config" \
        "$proof_dir/state" 2>/dev/null || {
        _mainframe_setup_error 'could not secure isolated temporary proof state'
        return 1
    }
    for private_path in \
        "$proof_dir" \
        "$proof_dir/home" \
        "$proof_dir/tmp" \
        "$proof_dir/config" \
        "$proof_dir/state"; do
        private_mode="$(_mainframe_setup_proof_path_mode "$private_path" || true)"
        [[ "$private_mode" == 700 ]] || {
            _mainframe_setup_error 'temporary proof state is not private mode 700'
            return 1
        }
    done

    nonce="$(_mainframe_setup_proof_nonce)" || {
        if _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir"; then
            proof_dir=""
        fi
        _mainframe_setup_error 'could not generate the private AWM continuity nonce'
        return 1
    }

    if ! broker_output="$(
        TMPDIR="$proof_dir/tmp" \
        MAINFRAME_INVOKE_AUDIT_LOG="$proof_dir/invocations.jsonl" \
            "$cli" invoke mf:std:pure-string:to_lower \
                --input-json '{"value":"HELLO Agent"}' 2>/dev/null
    )" || [[ "$broker_output" != 'hello agent' ]]; then
        if _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir" \
            >/dev/null 2>&1; then
            proof_dir=""
        fi
        _mainframe_setup_error 'reviewed pure invocation proof failed'
        return 1
    fi

    if ! _mainframe_setup_proof_awm_exec \
        "$env_bin" "$BASH" "$cli" "$proof_dir" "$project" \
        ensure >/dev/null 2>&1; then
        if _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir"; then
            proof_dir=""
        fi
        _mainframe_setup_error 'ephemeral AWM continuity proof could not initialize'
        return 1
    fi
    if ! _mainframe_setup_proof_awm_exec \
        "$env_bin" "$BASH" "$cli" "$proof_dir" "$project" \
        checkpoint mainframe-first-run-continuity "$nonce" \
        --importance high >/dev/null 2>&1; then
        if _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir"; then
            proof_dir=""
        fi
        _mainframe_setup_error 'ephemeral AWM continuity proof could not checkpoint'
        return 1
    fi

    retrieval_status=0
    if [[ "${_MAINFRAME_SETUP_TEST_FORCE_AWM_RETRIEVAL_FAILURE:-0}" == 1 &&
          -n "${BATS_TEST_FILENAME:-}" && -n "${BATS_TEST_TMPDIR:-}" ]]; then
        retrieval_status=97
        retrieved=""
    elif retrieved="$(_mainframe_setup_proof_awm_retrieve \
        "$env_bin" "$BASH" "$cli" "$proof_dir" "$project" 2>/dev/null)"; then
        :
    else
        retrieval_status=$?
    fi
    if (( retrieval_status != 0 )) || [[ "$retrieved" != "$nonce" ]]; then
        if _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir"; then
            proof_dir=""
        fi
        _mainframe_setup_error 'ephemeral AWM fresh-process retrieval failed'
        return 1
    fi

    if ! _mainframe_setup_proof_cleanup "$proof_base" "$proof_dir"; then
        _mainframe_setup_error 'temporary AWM and broker proof state could not be removed safely'
        return 1
    fi
    proof_dir=""
    trap - EXIT HUP INT TERM
    printf 'Reviewed invocation: PASS (fixed pure contract; output=%s)\n' "$broker_output"
    printf 'Durable memory:     PASS (fixed key retrieved by a fresh Bash process)\n'
    printf 'Temporary state:    REMOVED (private mode 700)\n'

    declare -F agent_gate_classify >/dev/null 2>&1 || {
        _mainframe_setup_error 'the shell policy classifier is unavailable'
        return 1
    }
    classification="$(
        AGENT_GATE_BLOCK_TIER=high \
            agent_gate_classify 'terraform destroy -auto-approve'
    )" || {
        _mainframe_setup_error 'shell policy classification failed'
        return 1
    }
    if ! "$_MAINFRAME_CLI_JQ" -e '
      . == {risk:"high", rule:"terraform-destroy", blocked:true}
    ' <<< "$classification" >/dev/null 2>&1; then
        _mainframe_setup_error 'shell policy proof returned an unexpected decision'
        return 1
    fi
    printf 'Shell policy:       PASS (classification only; canary not executed; rule=terraform-destroy)\n'

    printf '\nConcise integration discovery\n'
    _mainframe_setup_proof_pi_summary "$project" "$discovery_path"
    _mainframe_setup_proof_host_summary "$project" "$discovery_path"
    next_action="${_MAINFRAME_SETUP_PROOF_PI_ACTION:-}"
    [[ -n "$next_action" ]] || \
        next_action="${_MAINFRAME_SETUP_PROOF_HOST_ACTION:-}"
    if [[ -z "$next_action" ]]; then
        printf -v next_action 'mainframe setup --project %q' "$project"
    fi
    printf 'Next safe command:  %s\n' "$next_action"
    printf '\nAgent improvement/adoption: UNVERIFIED (mechanism proof only; no coding agent ran)\n'
    printf '\nLive host protection: UNVERIFIED\n'
    printf 'No host or Pi process was executed. No lasting project, Pi, AWM, shell-profile,\n'
    printf 'agent, audit, or network state remains; temporary AWM and broker state were removed.\n'
)

_mainframe_setup_error() {
    printf 'MAINFRAME setup: %s\n' "$*" >&2
}

_mainframe_setup_hosts() {
    printf '%s\n' codex claude-code copilot gemini
}

_mainframe_setup_host_supported() {
    case "${1:-}" in
        codex|claude-code|copilot|gemini) return 0 ;;
        *) return 1 ;;
    esac
}

_mainframe_setup_target_supported() {
    [[ "${1:-}" == pi ]] || _mainframe_setup_host_supported "${1:-}"
}

_mainframe_setup_host_cli_name() {
    case "${1:-}" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_setup_host_marker_paths() {
    case "${1:-}" in
        codex)
            printf '%s\n' 'AGENTS.md' '.codex/hooks.json'
            ;;
        claude-code)
            printf '%s\n' 'CLAUDE.md' '.claude/settings.json'
            ;;
        copilot)
            printf '%s\n' '.github/copilot-instructions.md' '.github/hooks/mainframe.json'
            ;;
        gemini)
            printf '%s\n' 'GEMINI.md' '.gemini/settings.json'
            ;;
        *) return 1 ;;
    esac
}

_mainframe_setup_executable_path() {
    local name="$1"
    local search_path="${2:-${PATH:-}}"
    local path=""

    path="$(PATH="$search_path" type -P "$name" 2>/dev/null || true)"
    if [[ -n "$path" && "$path" == /* && -x "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    return 1
}

_mainframe_setup_shell_allowed() {
    local shell_name="$1" executable="$2"

    case "$shell_name:$executable" in
        bash:/usr/bin/bash|bash:/bin/bash|bash:/usr/local/bin/bash|\
        bash:/opt/homebrew/Cellar/*/bin/bash|bash:/usr/local/Cellar/*/bin/bash|\
        bash:/home/linuxbrew/.linuxbrew/Cellar/*/bin/bash|bash:/nix/store/*/bin/bash|\
        zsh:/usr/bin/zsh|zsh:/bin/zsh|zsh:/usr/local/bin/zsh|\
        zsh:/opt/homebrew/Cellar/*/bin/zsh|zsh:/usr/local/Cellar/*/bin/zsh|\
        zsh:/home/linuxbrew/.linuxbrew/Cellar/*/bin/zsh|zsh:/nix/store/*/bin/zsh)
            return 0
            ;;
        *) return 1 ;;
    esac
}

_mainframe_setup_marker_summary() {
    local host="$1"
    local project="$2"
    local rel summary=""

    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if [[ -e "$project/$rel" || -L "$project/$rel" ]]; then
            if [[ -n "$summary" ]]; then
                summary+=", $rel"
            else
                summary="$rel"
            fi
        fi
    done < <(_mainframe_setup_host_marker_paths "$host")

    printf '%s\n' "${summary:-none}"
}

_mainframe_setup_shell_report() {
    local project="$1" discovery_path="$2"
    local shell_name candidate resolved version state detail

    printf 'Shell discovery\n'
    printf '  Login shell: %s\n' "${SHELL:-not set}"
    printf '  %-6s %-12s %s\n' 'SHELL' 'STATE' 'DETAIL'

    for shell_name in bash zsh; do
        candidate=""
        if [[ "$shell_name" == 'bash' && -n "${MAINFRAME_BASH:-}" ]]; then
            if [[ "$MAINFRAME_BASH" == /* && -x "$MAINFRAME_BASH" ]]; then
                candidate="$MAINFRAME_BASH"
            else
                candidate="$(_mainframe_setup_executable_path \
                    "$MAINFRAME_BASH" "$discovery_path" || true)"
            fi
        fi
        [[ -n "$candidate" ]] || \
            candidate="$(_mainframe_setup_executable_path \
                "$shell_name" "$discovery_path" || true)"
        if [[ -z "$candidate" ]]; then
            printf '  %-6s %-12s %s\n' "$shell_name" 'missing' 'not found on PATH'
            continue
        fi
        resolved="$(_mainframe_launch_resolve_executable "$candidate" || true)"
        if [[ -z "$resolved" ]]; then
            printf '  %-6s %-12s %s\n' \
                "$shell_name" 'unsafe' 'could not safely resolve executable'
            continue
        fi
        if [[ "$project" == / || "$resolved" == "$project" ||
              "$resolved" == "$project/"* ]]; then
            printf '  %-6s %-12s %s\n' \
                "$shell_name" 'unsafe' 'project-controlled executable was not run'
            continue
        fi
        if ! _mainframe_setup_shell_allowed "$shell_name" "$resolved"; then
            printf '  %-6s %-12s %s\n' \
                "$shell_name" 'unreviewed' "$resolved (not executed)"
            continue
        fi
        candidate="$resolved"

        if [[ "$shell_name" == "bash" ]]; then
            # shellcheck disable=SC2016 # Evaluated by the discovered Bash process.
            version="$("$candidate" --noprofile --norc -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null || true)"
            if "$candidate" --noprofile --norc -c '
                (( BASH_VERSINFO[0] > 4 )) ||
                (( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ))
            ' >/dev/null 2>&1; then
                state='ready'
            else
                state='unsupported'
            fi
            detail="$candidate (${version:-version unavailable})"
        else
            version="$("$candidate" --version 2>/dev/null || true)"
            state='available'
            detail="$candidate (${version:-version unavailable})"
        fi
        printf '  %-6s %-12s %s\n' "$shell_name" "$state" "$detail"
    done
}

_mainframe_setup_pi_load_manager() {
    local manager="$MAINFRAME_ROOT/lib/pi.sh"

    if declare -F mainframe_pi_status >/dev/null 2>&1 &&
       declare -F mainframe_pi_install >/dev/null 2>&1; then
        return 0
    fi
    [[ -f "$manager" && -r "$manager" ]] || return 1
    # shellcheck disable=SC1090 # MAINFRAME_ROOT is the canonical CLI root.
    source "$manager" || return 1
    declare -F mainframe_pi_status >/dev/null 2>&1 &&
        declare -F mainframe_pi_install >/dev/null 2>&1
}

_mainframe_setup_kv_value() {
    local text="$1" wanted="$2" line

    while IFS= read -r line; do
        case "$line" in
            "$wanted"=*) printf '%s\n' "${line#*=}"; return 0 ;;
        esac
    done <<< "$text"
    return 1
}

# Pi is intentionally not added to the project-hook host table. Its extension
# and skill are a user package, so discovery reports them in a separate section
# and never executes the discovered Pi binary.
_mainframe_setup_pi_report() {
    local project="$1" discovery_path="$2"
    local pi_cli pi_resolved cli_detail package_state package_detail
    local status_text agent_dir pi_actionable=false

    pi_cli="$(_mainframe_setup_executable_path pi "$discovery_path" || true)"
    if [[ -z "$pi_cli" ]]; then
        cli_detail='missing (not found on PATH)'
    else
        pi_resolved="$(_mainframe_launch_resolve_executable "$pi_cli" || true)"
        if [[ -z "$pi_resolved" ]]; then
            cli_detail='unsafe (could not safely resolve executable; not executed)'
        elif [[ "$project" == / || "$pi_cli" == "$project" ||
                "$pi_cli" == "$project/"* || "$pi_resolved" == "$project" ||
                "$pi_resolved" == "$project/"* ]]; then
            cli_detail="repo-controlled ($pi_cli; not executed)"
        else
            cli_detail="found ($pi_resolved; discovered only, not executed)"
            pi_actionable=true
        fi
    fi

    package_state='inspection-failed'
    package_detail='run mainframe pi status for details'
    if _mainframe_setup_pi_load_manager; then
        agent_dir="$(_mainframe_pi_agent_dir 2>/dev/null || true)"
        if [[ -n "$agent_dir" && ! -e "$agent_dir" && ! -L "$agent_dir" ]]; then
            package_state='not-initialized'
            package_detail="$agent_dir does not exist"
        elif status_text="$(
            cd -- "$project" 2>/dev/null && mainframe_pi_status 2>/dev/null
        )"; then
            package_state="$(_mainframe_setup_kv_value \
                "$status_text" state 2>/dev/null || printf 'inspection-failed')"
            package_detail="$(_mainframe_setup_kv_value \
                "$status_text" agent_dir 2>/dev/null || printf 'agent directory unavailable')"
        fi
    else
        package_state='manager-unavailable'
        package_detail="$MAINFRAME_ROOT/lib/pi.sh"
    fi

    printf '\nPi integration (user package; separate from project hooks)\n'
    printf '  CLI:     %s\n' "$cli_detail"
    printf '  Package: %s (%s)\n' "$package_state" "$package_detail"
    printf '  Pi discovery is read-only and never runs the Pi CLI.\n'
    _MAINFRAME_SETUP_PI_PACKAGE_STATE="$package_state"
    _MAINFRAME_SETUP_PI_ACTIONABLE="$pi_actionable"
    if [[ "$package_state" == not-initialized ]]; then
        if [[ "$pi_actionable" == true ]]; then
            printf '  Pi must create its user agent directory before MAINFRAME can preview activation.\n'
            printf '  Exact next action:\n'
            printf '    pi\n'
            printf '  After Pi starts, exit it and run:\n'
            printf '    mainframe pi doctor\n'
        else
            printf '  Install or safely expose Pi, run it once, and then rerun this discovery.\n'
            printf '  MAINFRAME did not print a Pi execution command because no safe Pi CLI was found.\n'
        fi
        return 0
    fi
    if [[ "$pi_actionable" != true ]]; then
        printf '  Install or safely expose Pi before activating its MAINFRAME package.\n'
        printf '  Diagnostic command:\n'
        printf '    mainframe pi doctor\n'
        return 0
    fi
    printf '  Exact next commands:\n'
    printf '    mainframe pi status\n'
    printf '    mainframe pi doctor\n'
    case "$package_state" in
        ready)
            printf '  Disk configuration is canonical; reload or restart Pi, then run:\n'
            printf '    /mainframe doctor\n'
            ;;
        project-collision|project-legacy)
            printf '  Review the project-local .pi override separately; no user-scope apply command is offered.\n'
            ;;
        inspection-failed|manager-unavailable)
            printf '  Diagnosis must succeed before MAINFRAME offers an apply command.\n'
            ;;
        *)
            printf '    mainframe pi install --dry-run\n'
            ;;
    esac
}

_mainframe_setup_pi_flow() {
    local project="$1" discovery_path="$2" dry_run="$3" assume_yes="$4"

    printf 'MAINFRAME Pi Setup\n'
    printf 'Project context: %s (collision inspection only)\n' "$project"
    printf 'Pi uses a user-scoped package flow, not project hook onboarding.\n'

    if [[ "$dry_run" != true && "$assume_yes" != true ]]; then
        _mainframe_setup_pi_report "$project" "$discovery_path"
        if [[ "${_MAINFRAME_SETUP_PI_ACTIONABLE:-false}" == true ]]; then
            case "${_MAINFRAME_SETUP_PI_PACKAGE_STATE:-inspection-failed}" in
                not-installed|legacy|duplicate|upgrade-needed|collision|noncanonical|inactive)
                    printf '  Apply only after reviewing the preview:\n'
                    printf '    mainframe pi install --yes\n'
                    ;;
            esac
        fi
        return 0
    fi

    if ! _mainframe_setup_pi_load_manager; then
        _mainframe_setup_error 'Pi package manager is unavailable'
        return 1
    fi
    if [[ "$dry_run" == true ]]; then
        (cd -- "$project" && mainframe_pi_install --dry-run)
    else
        (cd -- "$project" && mainframe_pi_install --yes)
    fi
}

_mainframe_setup_discovery() {
    local project="$1" runtime_policy="${2:-auto}"
    local discovery_path="${3:-${PATH:-}}"
    local cli host host_cli_name host_cli host_cli_resolved host_cli_state
    local host_compatibility marker_summary protection_state
    local doctor_state awm_state detected=false managed_state managed_detail
    local selected_state selected_source
    local -a detected_hosts=()
    local -A launch_ready=()
    local -A managed_states=()
    local -A runtime_states=()

    cli="$(_mainframe_onboard_cli)" || return 1

    # The nested doctor runs on the fixed helper PATH by design, so verify the
    # selected shell/profile identity in this original discovery process too.
    # That preserves the caller's PATH as inert data without executing from it.
    local shell_identity_ready=true shell_identity_state=not-ready
    if [[ -f "$MAINFRAME_ROOT/lib/shell.sh" && ! -L "$MAINFRAME_ROOT/lib/shell.sh" ]]; then
        # shellcheck source=lib/shell.sh
        source "$MAINFRAME_ROOT/lib/shell.sh"
        if _mainframe_shell_doctor_check >/dev/null 2>&1; then
            shell_identity_state=ready
        else
            shell_identity_ready=false
            shell_identity_state="${_MAINFRAME_SHELL_OVERALL:-not-ready}"
        fi
    else
        shell_identity_ready=false
    fi
    if "$cli" doctor >/dev/null 2>&1 && [[ "$shell_identity_ready" == true ]]; then
        doctor_state='ready'
    elif [[ "$shell_identity_state" == reload-required ]]; then
        doctor_state='reload-required'
    else
        doctor_state='not-ready'
    fi
    if "$cli" awm project status --project "$project" >/dev/null 2>&1; then
        awm_state='existing'
    else
        awm_state='not-initialized'
    fi

    printf 'MAINFRAME Guided Setup\n'
    printf 'Project: %s\n' "$project"
    printf 'Mode: discovery only (strictly read-only)\n\n'
    printf 'Install doctor: %s\n' "$doctor_state"
    if [[ "$doctor_state" == reload-required ]]; then
        printf '  Next: start a fresh shell or restart the parent app, then run mainframe doctor.\n'
    fi
    printf 'Project AWM:    %s (read-only status)\n\n' "$awm_state"
    _mainframe_setup_shell_report "$project" "$discovery_path"
    _mainframe_setup_pi_report "$project" "$discovery_path"

    printf '\nSupported host discovery\n'
    printf '  %-13s %-14s %-11s %s\n' 'HOST' 'CLI' 'PROTECTION' 'PROJECT MARKERS'
    while IFS= read -r host; do
        host_cli_name="$(_mainframe_setup_host_cli_name "$host")"
        host_cli="$(_mainframe_setup_executable_path \
            "$host_cli_name" "$discovery_path" || true)"
        host_cli_resolved=""
        host_cli_state='missing'
        host_compatibility='not found on PATH'
        if [[ -n "$host_cli" ]]; then
            host_cli_resolved="$(_mainframe_launch_resolve_executable "$host_cli" || true)"
            if [[ -z "$host_cli_resolved" ]]; then
                host_cli_state='unsafe'
                host_compatibility='could not safely resolve executable'
            elif [[ "$host_cli_resolved" == "$project" ||
                    "$host_cli_resolved" == "$project/"* ]]; then
                host_cli_state='repo-controlled'
                host_compatibility='executable resolves inside the project'
            elif _mainframe_launch_host_compatible \
                "$host" "$host_cli_resolved" "$project" "$discovery_path"; then
                host_cli_state='certified'
                host_compatibility="pinned version $_MAINFRAME_HOST_VERSION; $_MAINFRAME_HOST_IDENTITY"
            else
                host_cli_state='incompatible'
                host_compatibility="${_MAINFRAME_HOST_ERROR:-artifact authentication failed}"
            fi
        fi
        _mainframe_host_probe_managed "$host" "$project" || true
        managed_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
        managed_detail="$_MAINFRAME_RUNTIME_MANAGED_DETAIL"
        managed_states["$host"]="$managed_state"
        _mainframe_host_resolve \
            "$host" "$project" "$runtime_policy" "$discovery_path" || true
        if [[ -n "${_MAINFRAME_RUNTIME_MANAGED_STATE:-}" ]]; then
            managed_state="$_MAINFRAME_RUNTIME_MANAGED_STATE"
            managed_detail="$_MAINFRAME_RUNTIME_MANAGED_DETAIL"
            managed_states["$host"]="$managed_state"
        fi
        selected_state="$_MAINFRAME_RUNTIME_SELECTED_STATE"
        selected_source="${_MAINFRAME_RUNTIME_SELECTED_SOURCE:-none}"
        runtime_states["$host"]="$selected_state"
        marker_summary="$(_mainframe_setup_marker_summary "$host" "$project")"
        if "$cli" protect status "$host" --project "$project" >/dev/null 2>&1; then
            protection_state='ready'
        else
            protection_state='not-ready'
        fi

        if [[ -n "$host_cli" ]]; then
            printf '  %-13s %-14s %-11s %s\n' \
                "$host" "$host_cli_state" "$protection_state" "$marker_summary"
            printf '    CLI: %s\n' "${host_cli_resolved:-$host_cli}"
            printf '    Compatibility: %s\n' "$host_compatibility"
            printf '    Managed payload: %s (%s)\n' "$managed_state" "$managed_detail"
            printf '    Runtime selection: %s (%s, policy=%s)\n' \
                "$selected_state" "$selected_source" "$runtime_policy"
            detected=true
        else
            printf '  %-13s %-14s %-11s %s\n' \
                "$host" 'missing' "$protection_state" "$marker_summary"
            printf '    Managed payload: %s (%s)\n' "$managed_state" "$managed_detail"
            printf '    Runtime selection: %s (%s, policy=%s)\n' \
                "$selected_state" "$selected_source" "$runtime_policy"
        fi
        if [[ "$marker_summary" != 'none' ]]; then
            detected=true
        fi
        if [[ "$detected" == 'true' ]]; then
            detected_hosts+=("$host")
        fi
        if [[ "$selected_state" == 'ready' && "$protection_state" == 'ready' &&
              "$awm_state" == 'existing' ]] &&
           declare -F _mainframe_launch_instruction_current >/dev/null 2>&1 &&
           _mainframe_launch_instruction_current "$host" "$project"; then
            launch_ready["$host"]='true'
        else
            launch_ready["$host"]='false'
        fi
        detected=false
    done < <(_mainframe_setup_hosts)

    printf '\n'
    if [[ ${#detected_hosts[@]} -eq 0 ]]; then
        printf 'Detected candidates: none\n'
        printf 'No supported host CLI or project marker was detected.\n'
        while IFS= read -r host; do
            detected_hosts+=("$host")
        done < <(_mainframe_setup_hosts)
    else
        printf 'Detected candidates:'
        printf ' %s' "${detected_hosts[@]}"
        printf '\n'
    fi
    printf 'No host was selected. Discovery never auto-selects or mutates a project.\n'
    printf '\nExact next commands (choose one host):\n'
    while IFS= read -r host; do
        if [[ "${runtime_states[$host]:-unavailable}" != 'ready' ]]; then
            printf '  # %s runtime is %s under policy %s\n' \
                "$host" "${runtime_states[$host]:-unavailable}" "$runtime_policy"
            printf '  mainframe host status %q --runtime %q\n' \
                "$host" "$runtime_policy"
            _mainframe_host_recovery_hints \
                "$host" "$runtime_policy" \
                "${managed_states[$host]:-unsupported}" "$project"
        elif [[ "${launch_ready[$host]:-false}" == 'true' ]]; then
            printf '  mainframe launch %q --project %q --runtime %q --dry-run\n' \
                "$host" "$project" "$runtime_policy"
            printf '  mainframe launch %q --project %q --runtime %q\n' \
                "$host" "$project" "$runtime_policy"
        else
            printf '  mainframe setup --project %q --host %q --runtime %q --dry-run\n' \
                "$project" "$host" "$runtime_policy"
            printf '  mainframe setup --project %q --host %q --runtime %q\n' \
                "$project" "$host" "$runtime_policy"
        fi
    done < <(_mainframe_setup_hosts)
}

mainframe_setup() {
    local host="" project="" host_set=false project_set=false
    local runtime_policy=auto runtime_set=false
    local dry_run=false assume_yes=false proof=false
    local canonical_project recovery_managed_state
    local discovery_path="${_MAINFRAME_SETUP_DISCOVERY_PATH:-${PATH:-}}"
    local -a onboard_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                if [[ "$host_set" == 'true' || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_setup_error '--host requires exactly one value'
                    return 2
                fi
                host="$2"
                host_set=true
                shift 2
                ;;
            --project)
                if [[ "$project_set" == 'true' || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_setup_error '--project requires exactly one directory'
                    return 2
                fi
                project="$2"
                project_set=true
                shift 2
                ;;
            --proof)
                if [[ "$proof" == true ]]; then
                    _mainframe_setup_error '--proof may be specified only once'
                    return 2
                fi
                proof=true
                shift
                ;;
            --runtime)
                if [[ "$runtime_set" == 'true' || $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
                    _mainframe_setup_error '--runtime requires exactly one source'
                    return 2
                fi
                runtime_policy="$2"
                runtime_set=true
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --yes)
                assume_yes=true
                shift
                ;;
            -h|--help)
                _mainframe_setup_usage
                return 0
                ;;
            *)
                _mainframe_setup_error "unknown option or argument: $1"
                _mainframe_setup_usage >&2
                return 2
                ;;
        esac
    done

    if [[ "$project_set" != 'true' ]]; then
        _mainframe_setup_error '--project is required'
        _mainframe_setup_usage >&2
        return 2
    fi
    if [[ "$host_set" == 'true' ]] && ! _mainframe_setup_target_supported "$host"; then
        _mainframe_setup_error \
            "unsupported host: $host (supported: codex, claude-code, copilot, gemini, pi)"
        return 2
    fi
    case "$runtime_policy" in
        auto|managed|system) ;;
        *)
            _mainframe_setup_error \
                "unsupported runtime source: $runtime_policy (supported: auto, managed, system)"
            return 2
            ;;
    esac
    if [[ ! -d "$project" ]]; then
        _mainframe_setup_error "project directory not found: $project"
        return 2
    fi
    canonical_project="$(cd -- "$project" 2>/dev/null && pwd -P)" || {
        _mainframe_setup_error "could not resolve project directory: $project"
        return 2
    }

    if [[ "$proof" == true ]] &&
       [[ "$host_set" == true || "$runtime_set" == true ||
          "$dry_run" == true || "$assume_yes" == true ]]; then
        _mainframe_setup_error \
            '--proof is hostless and cannot be combined with --host, --runtime, --dry-run, or --yes'
        return 2
    fi

    if [[ "$host_set" == 'true' && "$host" == pi ]]; then
        if [[ "$runtime_set" == true ]]; then
            _mainframe_setup_error \
                "--runtime does not apply to Pi's user-package flow; use mainframe pi status"
            return 2
        fi
        if [[ "$dry_run" == true && "$assume_yes" == true ]]; then
            _mainframe_setup_error \
                'choose exactly one of --dry-run or --yes for Pi'
            return 2
        fi
        _mainframe_setup_pi_flow \
            "$canonical_project" "$discovery_path" "$dry_run" "$assume_yes"
        return $?
    fi

    if ! _mainframe_enforce_bind_jq "$canonical_project" "$discovery_path"; then
        _mainframe_setup_error \
            "trusted host metadata is unavailable: ${_MAINFRAME_ENFORCE_BIND_ERROR:-jq binding failed}"
        return 1
    fi

    if [[ "$host_set" != 'true' ]]; then
        if [[ "$proof" == true ]]; then
            _mainframe_setup_proof "$canonical_project" "$discovery_path"
            return $?
        fi
        _mainframe_setup_discovery \
            "$canonical_project" "$runtime_policy" "$discovery_path"
        return $?
    fi

    if ! _mainframe_host_resolve \
        "$host" "$canonical_project" "$runtime_policy" "$discovery_path"; then
        recovery_managed_state="${_MAINFRAME_RUNTIME_MANAGED_STATE:-}"
        if [[ -z "$recovery_managed_state" ]]; then
            _mainframe_host_probe_managed "$host" "$canonical_project" || true
            recovery_managed_state="${_MAINFRAME_RUNTIME_MANAGED_STATE:-unsupported}"
        fi
        _mainframe_setup_error \
            "${_MAINFRAME_RUNTIME_ERROR:-host runtime resolution failed}; onboarding was not changed"
        printf 'Inspect host runtime state:\n  mainframe host status %q --runtime %q\n' \
            "$host" "$runtime_policy" >&2
        _mainframe_host_recovery_hints \
            "$host" "$runtime_policy" \
            "$recovery_managed_state" "$canonical_project" >&2
        return 1
    fi
    printf 'Runtime source: %s (policy=%s, pinned version %s)\n' \
        "$_MAINFRAME_RUNTIME_SELECTED_SOURCE" "$runtime_policy" \
        "$_MAINFRAME_RUNTIME_VERSION"

    onboard_args=(--host "$host" --project "$canonical_project")
    [[ "$dry_run" == 'true' ]] && onboard_args+=(--dry-run)
    [[ "$assume_yes" == 'true' ]] && onboard_args+=(--yes)
    mainframe_onboard "${onboard_args[@]}"
}

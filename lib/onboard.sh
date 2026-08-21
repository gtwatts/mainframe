#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/onboard.sh - Explicit-consent fresh-machine onboarding
# =============================================================================
# Thin orchestration over the existing doctor, activate, agent-hook, and protect
# surfaces. This library deliberately does not install, launch, or trust an AI
# host and never treats static configuration as proof that a host loaded a hook.
# =============================================================================

[[ -n "${_MAINFRAME_ONBOARD_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_ONBOARD_LOADED=1

_mainframe_onboard_usage() {
    cat <<'EOF'
Usage: mainframe onboard --host <host> --project <dir> [--dry-run] [--yes]

Hosts: codex, claude-code, copilot, gemini

Options:
  --host HOST       Configure one supported enforced host (required)
  --project DIR     Existing project directory to configure (required)
  --dry-run         Run health checks and preview changes without writing
  --yes             Explicitly approve changes in a non-interactive shell
  -h, --help        Show this help

Onboarding always previews merge-safe `activate --enforce` changes before
consent. After consent it creates or resumes a private AWM session for the
canonical project, then verifies the installed gateway and static project
configuration. Host-native trust and runtime loading still require a host
restart, review, and disposable canary.
EOF
}

_mainframe_onboard_error() {
    printf 'MAINFRAME onboard: %s\n' "$*" >&2
}

_mainframe_onboard_consent_is_yes() {
    local answer="${1:-}"
    answer="${answer,,}"
    [[ "$answer" == "y" || "$answer" == "yes" ]]
}

_mainframe_onboard_cli() {
    local root="${MAINFRAME_ROOT:-}"

    if [[ -z "$root" || ! -x "$root/bin/mainframe" ]]; then
        _mainframe_onboard_error "the installed MAINFRAME CLI could not be resolved"
        return 1
    fi
    printf '%s\n' "$root/bin/mainframe"
}

_mainframe_onboard_gateway_format() {
    case "${1:-}" in
        codex) printf 'codex\n' ;;
        claude-code) printf 'claude\n' ;;
        copilot) printf 'copilot\n' ;;
        gemini) printf 'gemini\n' ;;
        *) return 1 ;;
    esac
}

_mainframe_onboard_gateway_payload() {
    local host="$1"
    local command_text="$2"
    local jq_bin="${MAINFRAME_AGENT_JQ:-}"

    [[ "$jq_bin" == /* && -x "$jq_bin" ]] || return 1

    case "$host" in
        codex|claude-code)
            "$jq_bin" -cn --arg command "$command_text" \
                '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}'
            ;;
        gemini)
            "$jq_bin" -cn --arg command "$command_text" \
                '{hook_event_name:"BeforeTool",tool_name:"run_shell_command",tool_input:{command:$command}}'
            ;;
        copilot)
            "$jq_bin" -cn --arg command "$command_text" \
                '{toolName:"bash",toolArgs:({command:$command} | tojson)}'
            ;;
        *) return 1 ;;
    esac
}

_mainframe_onboard_print_rollback() {
    local host="$1"
    local project="$2"

    printf 'Rollback preview:\n  mainframe deactivate %q --project %q --enforce --dry-run\n' \
        "$host" "$project"
    printf 'Rollback apply:\n  mainframe deactivate %q --project %q --enforce\n' \
        "$host" "$project"
    printf 'Deactivation leaves private project-memory history intact.\n'
    printf 'Project-memory reads remain available only through the reviewed control-plane route for %q; returned memory is non-authoritative.\n' "$project"
}

_mainframe_onboard_print_host_guidance() {
    local host="$1"
    local project="$2"

    printf '\nHost runtime load:     UNVERIFIED\n'
    printf "Use MAINFRAME's fail-closed launcher from a fresh terminal:\n"
    printf '  mainframe launch %q --project %q\n' "$host" "$project"
    printf 'The launcher rechecks current instructions, AWM, and static protection before exec.\n'
    case "$host" in
        codex)
            printf 'Codex: open /hooks, review and trust the exact MAINFRAME hook hash, then run a disposable canary.\n'
            ;;
        claude-code)
            printf 'Claude Code: accept workspace trust, inspect the PreToolUse/Bash hook, then run a disposable canary.\n'
            ;;
        copilot)
            printf 'Copilot: trust the folder, inspect preToolUse, then run a disposable canary.\n'
            printf 'Warning: Copilot documents preToolUse hook timeouts as fail-open.\n'
            ;;
        gemini)
            printf 'Gemini: inspect BeforeTool/run_shell_command, then run a disposable canary.\n'
            ;;
    esac

    case "${SHELL:-}" in
        */zsh)
            # shellcheck disable=SC2016 # Print a copy-paste command, not this process's HOME.
            printf 'Shell: open a new terminal after installation; optionally source "$HOME/.zshrc" yourself.\n'
            ;;
        */bash)
            # shellcheck disable=SC2016 # Print a copy-paste command, not this process's HOME.
            printf 'Shell: open a new terminal after installation; optionally source "$HOME/.bashrc" yourself.\n'
            ;;
        *)
            printf 'Shell: open a new terminal after installation before launching the host.\n'
            ;;
    esac
}

_mainframe_onboard_gateway_canary() {
    local host="$1" project="$2"
    local format allow_payload deny_payload
    local allow_output deny_output deny_status
    local deny_target="${TMPDIR:-/tmp}/mainframe-onboard-never-execute-$$-${RANDOM}"

    if ! _mainframe_enforce_bind_runtime "$project"; then
        _mainframe_onboard_error \
            "privileged gateway runtime is not ready: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}"
        return 1
    fi
    format="$(_mainframe_onboard_gateway_format "$host")" || return 1
    allow_payload="$(_mainframe_onboard_gateway_payload "$host" 'git status --short')" || {
        _mainframe_onboard_error "could not build the benign gateway canary payload"
        return 1
    }
    deny_payload="$(_mainframe_onboard_gateway_payload "$host" "/bin/rm -rf $deny_target")" || {
        _mainframe_onboard_error "could not build the denied gateway canary payload"
        return 1
    }

    if allow_output="$(_mainframe_enforce_gateway_probe "$format" <<<"$allow_payload" 2>&1)"; then
        if [[ "$allow_output" != "{}" ]]; then
            _mainframe_onboard_error "benign gateway canary returned unexpected output: $allow_output"
            return 1
        fi
    else
        _mainframe_onboard_error "benign gateway canary failed: $allow_output"
        return 1
    fi

    if deny_output="$(_mainframe_enforce_gateway_probe "$format" <<<"$deny_payload" 2>&1)"; then
        deny_status=0
    else
        deny_status=$?
    fi
    if [[ "$deny_status" -ne 2 ]]; then
        _mainframe_onboard_error \
            "destructive gateway canary did not fail closed (exit=$deny_status): $deny_output"
        return 1
    fi
    if [[ -e "$deny_target" ]]; then
        _mainframe_onboard_error "destructive gateway canary target unexpectedly exists: $deny_target"
        return 1
    fi

    printf 'Privileged gateway:    VERIFIED (%s)\n' "$MAINFRAME_AGENT_GATEWAY"
    printf 'Policy byte seal:      VERIFIED (Bash, jq, gateway, safety policy)\n'
    printf 'Gateway allow canary:  PASS\n'
    printf 'Gateway deny canary:   PASS\n'
}

mainframe_onboard() {
    local host="" project="" host_set=false project_set=false
    local dry_run=false assume_yes=false answer=""
    local cli canonical_project doctor_output preview_output apply_output protect_output
    local awm_ensure_output awm_session_id
    local doctor_status preview_status apply_status protect_status
    local awm_ensure_status
    local audit_log policy_tier

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                if [[ "$host_set" == "true" || $# -lt 2 ]]; then
                    _mainframe_onboard_error "--host requires exactly one value"
                    return 2
                fi
                host="$2"
                host_set=true
                shift 2
                ;;
            --project)
                if [[ "$project_set" == "true" || $# -lt 2 ]]; then
                    _mainframe_onboard_error "--project requires exactly one directory"
                    return 2
                fi
                project="$2"
                project_set=true
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
                _mainframe_onboard_usage
                return 0
                ;;
            *)
                _mainframe_onboard_error "unknown option or argument: $1"
                _mainframe_onboard_usage >&2
                return 2
                ;;
        esac
    done

    if [[ "$host_set" != "true" || "$project_set" != "true" ]]; then
        _mainframe_onboard_error "both --host and --project are required"
        _mainframe_onboard_usage >&2
        return 2
    fi
    case "$host" in
        codex|claude-code|copilot|gemini) ;;
        all)
            _mainframe_onboard_error "--host all is not supported; onboard one host per consent decision"
            return 2
            ;;
        cursor|jetbrains|junie)
            _mainframe_onboard_error "$host is instruction-only and cannot be onboarded as protected"
            return 2
            ;;
        *)
            _mainframe_onboard_error \
                "unsupported host: $host (supported: codex, claude-code, copilot, gemini)"
            return 2
            ;;
    esac
    if [[ ! -d "$project" ]]; then
        _mainframe_onboard_error "project directory not found: $project"
        return 2
    fi
    canonical_project="$(cd -- "$project" 2>/dev/null && pwd -P)" || {
        _mainframe_onboard_error "could not resolve project directory: $project"
        return 2
    }
    cli="$(_mainframe_onboard_cli)" || return 1

    printf 'MAINFRAME Onboarding Preflight\n'
    printf 'Host:    %s\n' "$host"
    printf 'Project: %s\n\n' "$canonical_project"

    if ! _mainframe_enforce_bind_runtime "$canonical_project"; then
        _mainframe_onboard_error \
            "privileged gateway runtime is not ready: ${_MAINFRAME_ENFORCE_BIND_ERROR:-unknown error}; no project changes were attempted"
        return 1
    fi

    if doctor_output="$("$cli" doctor 2>&1)"; then
        doctor_status=0
    else
        doctor_status=$?
    fi
    printf '%s\n' "$doctor_output"
    if [[ "$doctor_status" -ne 0 ]]; then
        _mainframe_onboard_error "doctor failed; no project changes were attempted"
        return 1
    fi

    if preview_output="$("$cli" activate "$host" --project "$canonical_project" --enforce --dry-run 2>&1)"; then
        preview_status=0
    else
        preview_status=$?
    fi
    printf '\nActivation preview:\n%s\n' "$preview_output"
    if [[ "$preview_status" -ne 0 ]]; then
        _mainframe_onboard_error "activation preview failed; no project changes were attempted"
        return 1
    fi

    policy_tier="${MAINFRAME_AGENT_GATE_TIER:-medium}"
    audit_log="${MAINFRAME_AGENT_AUDIT_LOG:-${XDG_STATE_HOME:-${HOME:-}/.local/state}/mainframe/agent-gateway.jsonl}"
    printf '\nPolicy tier: %s\n' "$policy_tier"
    printf 'After consent, a synthetic allow/deny check will append decision-only records to:\n  %s\n' "$audit_log"
    printf 'After consent, a kernel-tracked, non-authoritative project-memory session will be created or resumed.\n'
    printf 'Project hook files may be committed and fail closed without launch-time MAINFRAME bindings.\n'
    printf 'Native host trust and runtime loading cannot be verified by this command.\n\n'
    _mainframe_onboard_print_rollback "$host" "$canonical_project"

    if [[ "$dry_run" == "true" ]]; then
        printf '\nDry run complete. No project files, AWM state, or audit records were changed.\n'
        return 0
    fi

    if [[ "$assume_yes" != "true" ]]; then
        if [[ ! -t 0 ]]; then
            _mainframe_onboard_error \
                "refusing non-interactive changes without --yes; use --dry-run to preview"
            return 2
        fi
        printf '\nApply these MAINFRAME-managed project changes and enable the %s shell gate? [y/N] ' \
            "$host" >&2
        if ! IFS= read -r answer; then
            _mainframe_onboard_error "consent was not provided; no changes were made"
            return 2
        fi
        if ! _mainframe_onboard_consent_is_yes "$answer"; then
            _mainframe_onboard_error "onboarding declined; no changes were made"
            return 2
        fi
    else
        printf '\nConsent: --yes\n'
    fi

    if ! _mainframe_onboard_gateway_canary "$host" "$canonical_project"; then
        _mainframe_onboard_error "gateway verification failed before project activation"
        _mainframe_onboard_print_rollback "$host" "$canonical_project" >&2
        return 1
    fi

    # Establish durable memory only after explicit consent, but before any
    # project-file mutation. Project-scoped AWM commands resolve this private
    # mapping on every invocation, so coding-agent shell process boundaries do
    # not discard the active session identity.
    if awm_ensure_output="$("$cli" awm project ensure --project "$canonical_project" 2>&1)"; then
        awm_ensure_status=0
    else
        awm_ensure_status=$?
    fi
    printf '\nAWM project session ensure:\n%s\n' "$awm_ensure_output"
    if [[ "$awm_ensure_status" -ne 0 ]]; then
        _mainframe_onboard_error \
            "AWM project session setup failed; no project changes were attempted"
        return 1
    fi

    # The compatible ensure presentation is delivered only after the kernel
    # validates the adapter receipt and appends durable provenance. All project
    # reads use the same reviewed route and remain non-authoritative data.
    awm_session_id="${awm_ensure_output##*$'\n'}"
    awm_session_id="${awm_session_id%$'\r'}"
    if [[ ! "$awm_session_id" =~ ^[0-9a-f]{12}$ ]]; then
        _mainframe_onboard_error \
            "durable project-memory receipt omitted its compatible session identity; no project changes were attempted"
        return 1
    fi
    printf 'AWM project session:  RECORDED (%s; non-authoritative)\n' "$awm_session_id"
    printf 'AWM project reads:    READY (durable control-plane; non-authoritative data)\n'

    if apply_output="$("$cli" activate "$host" --project "$canonical_project" --enforce 2>&1)"; then
        apply_status=0
    else
        apply_status=$?
    fi
    printf '\nActivation apply:\n%s\n' "$apply_output"
    if [[ "$apply_status" -ne 0 ]]; then
        _mainframe_onboard_error \
            "activation failed; inspect current state before choosing whether to roll back"
        _mainframe_onboard_print_rollback "$host" "$canonical_project" >&2
        return 1
    fi

    if protect_output="$("$cli" protect status "$host" --project "$canonical_project" 2>&1)"; then
        protect_status=0
    else
        protect_status=$?
    fi
    printf '\n%s\n' "$protect_output"
    if [[ "$protect_status" -ne 0 ]]; then
        _mainframe_onboard_error \
            "static readiness failed; activation remains visible and fail-closed pending review"
        _mainframe_onboard_print_rollback "$host" "$canonical_project" >&2
        return 1
    fi

    printf '\nMAINFRAME onboarding complete\n'
    printf 'Install health:        READY\n'
    printf 'Gateway adapter:       VERIFIED\n'
    printf 'AWM project session:   RECORDED (%s; non-authoritative)\n' "$awm_session_id"
    printf 'Project configuration: READY\n'
    _mainframe_onboard_print_host_guidance "$host" "$canonical_project"
    printf '\n'
    _mainframe_onboard_print_rollback "$host" "$canonical_project"
}

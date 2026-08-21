#!/usr/bin/env bash
# =============================================================================
# MAINFRAME Bash Completion
# =============================================================================
# Install:
#   source /path/to/mainframe/completions/mainframe.bash
#
# Or copy to system completion directory:
#   cp completions/mainframe.bash /etc/bash_completion.d/mainframe
#
# Or add to ~/.bashrc:
#   source "${MAINFRAME_ROOT:-$HOME/.mainframe}/completions/mainframe.bash"
# =============================================================================

_mainframe_completions() {
    local cur prev words cword candidate

    # Use bash-completion helper if available, otherwise manual parsing
    if declare -F _init_completion &>/dev/null; then
        _init_completion || return
    else
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    # Top-level commands (including aliases). Keep this in parity with the
    # dispatch table in bin/mainframe; tests/unit/installer.bats enforces it.
    local commands="version functions funcs list operations ops run invoke help info describe search find grep awm work count quickref qr signatures sigs fzf fuzzy browse explore tui doctor check health shell agent-hook agent-gateway protect host pi control-plane setup onboard launch activate deactivate benchmark bench test tests update upgrade release uninstall new init build"

    # Quickref options
    local quickref_opts="--list -l --all -a --search -s --json -j"
    local awm_commands="project init resume checkpoint discovery progress get summary context find handoff list status doctor export inspect migrate"
    local awm_project_actions="ensure session status checkpoint get discovery progress summary context find handoff close"
    local onboard_hosts="codex claude-code copilot gemini"
    local setup_hosts="$onboard_hosts pi"
    local managed_hosts="codex claude-code copilot"
    local onboard_opts="--host --project --dry-run --yes --help -h"
    local setup_opts="--host --project --proof --runtime --dry-run --yes --help -h"
    local launch_opts="--project --policy --runtime --dry-run --help -h"
    local work_opts="--project --tokens --format --help -h"
    local runtime_policies="auto managed system"
    local host_actions="status install remove restore"
    local shell_actions="status repair"
    local pi_actions="status doctor install remove restore help"
    local release_actions="readiness help"
    local control_plane_actions="run-create run-transition call-create call-request-approval approval-grant approval-consume trace-execute disposable-write-execute show"
    local upgrade_opts="--version --allow-downgrade --dry-run --confirm-agents-stopped --recover --journal --help -h"
    local uninstall_opts="--dry-run --purge --purge-state --dir --bin --shell-config --help -h"

    if [[ "${words[1]:-}" == "shell" ]]; then
        if (( cword == 2 )); then
            COMPREPLY=( $(compgen -W "$shell_actions" -- "$cur") )
            return
        fi
        case "$prev" in
            --shell)
                COMPREPLY=( $(compgen -W "bash zsh all" -- "$cur") )
                return
                ;;
            --zdotdir)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=( $(compgen -d -- "$cur") )
                return
                ;;
        esac
        if [[ "${words[2]:-}" == status ]]; then
            COMPREPLY=( $(compgen -W "--shell --zdotdir --json --help -h" -- "$cur") )
        elif [[ "${words[2]:-}" == repair ]]; then
            COMPREPLY=( $(compgen -W "--shell --zdotdir --dry-run --yes --help -h" -- "$cur") )
        fi
        return
    fi

    if [[ "${words[1]:-}" == "invoke" ]]; then
        case "$prev" in
            --input-json) return ;;
            --profile)
                COMPREPLY=( $(compgen -W "stable-core" -- "$cur") )
                return
                ;;
            --format)
                COMPREPLY=( $(compgen -W "raw broker-json-v1" -- "$cur") )
                return
                ;;
            --caller) return ;;
        esac
        if (( cword == 2 )); then
            local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
            local manifest_file="${mainframe_root}/MANIFEST.json"
            if [[ -f "$manifest_file" ]] && command -v jq &>/dev/null; then
                local canonical_ids
                canonical_ids=$(jq -r '
                    .exports | to_entries[] |
                    select(.value.contract_status == "reviewed" and
                           (.value.profiles | index("stable-core") != null)) |
                    .key
                ' "$manifest_file" 2>/dev/null)
                COMPREPLY=( $(compgen -W "$canonical_ids" -- "$cur") )
            fi
        else
            COMPREPLY=( $(compgen -W "--input-json --profile --format --caller --help -h" -- "$cur") )
        fi
        return
    fi

    if [[ "${words[1]:-}" == "release" ]]; then
        if (( cword == 2 )); then
            COMPREPLY=()
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$release_actions" -- "$cur")
        elif [[ "${words[2]:-}" == "readiness" ]]; then
            COMPREPLY=()
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "--json --help -h" -- "$cur")
        fi
        return
    fi

    if [[ "${words[1]:-}" == "control-plane" ]]; then
        if [[ "$prev" == "--ledger" ]]; then
            _filedir 2>/dev/null || COMPREPLY=( $(compgen -f -- "$cur") )
            return
        fi
        COMPREPLY=( $(compgen -W \
            "--ledger $control_plane_actions --help -h" -- "$cur") )
        return
    fi

    if [[ "${words[1]:-}" == "uninstall" ]]; then
        case "$prev" in
            --dir|--bin)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -d -- "$cur")
                return
                ;;
            --shell-config)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -f -- "$cur")
                return
                ;;
        esac
        COMPREPLY=()
        while IFS= read -r candidate; do
            COMPREPLY+=("$candidate")
        done < <(compgen -W "$uninstall_opts" -- "$cur")
        return
    fi

    if [[ "${words[1]:-}" == "upgrade" ]]; then
        case "$prev" in
            --version|--journal) return ;;
        esac
        COMPREPLY=()
        while IFS= read -r candidate; do
            COMPREPLY+=("$candidate")
        done < <(compgen -W "$upgrade_opts" -- "$cur")
        return
    fi

    if [[ "${words[1]:-}" == "host" ]]; then
        local host_action="${words[2]:-}"
        local word_index word
        local saw_download=false saw_package_dir=false
        local saw_dry_run=false saw_yes=false saw_json=false
        local saw_help=false saw_runtime=false saw_quarantine_id=false

        # Only completed words count as used. Keep completion aligned with the
        # lifecycle parser by withholding duplicates and mutually exclusive
        # alternatives after the operator has made a choice.
        for ((word_index = 3; word_index < cword; word_index++)); do
            word="${words[word_index]}"
            case "$word" in
                --download) saw_download=true ;;
                --package-dir) saw_package_dir=true ;;
                --dry-run) saw_dry_run=true ;;
                --yes) saw_yes=true ;;
                --json) saw_json=true ;;
                -h|--help) saw_help=true ;;
                --runtime) saw_runtime=true ;;
                --quarantine-id) saw_quarantine_id=true ;;
            esac
        done

        case "$prev" in
            --runtime)
                if [[ "$host_action" == "status" ]]; then
                    COMPREPLY=()
                    while IFS= read -r candidate; do
                        COMPREPLY+=("$candidate")
                    done < <(compgen -W "$runtime_policies" -- "$cur")
                    return
                fi
                ;;
            --package-dir)
                if [[ "$host_action" == "install" ]]; then
                    compopt -o dirnames 2>/dev/null || true
                    COMPREPLY=()
                    while IFS= read -r candidate; do
                        COMPREPLY+=("$candidate")
                    done < <(compgen -d -- "$cur")
                    return
                fi
                ;;
            --quarantine-id)
                if [[ "$host_action" == "restore" ]]; then
                    return
                fi
                ;;
        esac

        COMPREPLY=()
        if [[ "$cword" -eq 2 ]]; then
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$host_actions" -- "$cur")
            return
        fi

        local -a host_opts=()
        case "$host_action" in
            status)
                [[ "$saw_runtime" == true ]] || host_opts+=(--runtime)
                [[ "$saw_json" == true ]] || host_opts+=(--json)
                ;;
            install)
                if [[ "$saw_download" == false && "$saw_package_dir" == false ]]; then
                    host_opts+=(--download --package-dir)
                fi
                if [[ "$saw_dry_run" == false && "$saw_yes" == false ]]; then
                    host_opts+=(--dry-run --yes)
                fi
                [[ "$saw_json" == true ]] || host_opts+=(--json)
                ;;
            remove)
                if [[ "$saw_dry_run" == false && "$saw_yes" == false ]]; then
                    host_opts+=(--dry-run --yes)
                fi
                [[ "$saw_json" == true ]] || host_opts+=(--json)
                ;;
            restore)
                [[ "$saw_quarantine_id" == true ]] || host_opts+=(--quarantine-id)
                if [[ "$saw_dry_run" == false && "$saw_yes" == false ]]; then
                    host_opts+=(--dry-run --yes)
                fi
                [[ "$saw_json" == true ]] || host_opts+=(--json)
                ;;
            *) return ;;
        esac
        [[ "$saw_help" == true ]] || host_opts+=(--help -h)

        local host_candidates=""
        if [[ "$cword" -eq 3 ]]; then
            case "$host_action" in
                status) host_candidates="$onboard_hosts" ;;
                install|remove|restore) host_candidates="$managed_hosts" ;;
            esac
        fi
        while IFS= read -r candidate; do
            COMPREPLY+=("$candidate")
        done < <(compgen -W "$host_candidates ${host_opts[*]}" -- "$cur")
        return
    fi

    if [[ "${words[1]:-}" == "pi" ]]; then
        COMPREPLY=()
        if [[ "$cword" -eq 2 ]]; then
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$pi_actions" -- "$cur")
            return
        fi

        case "${words[2]:-}" in
            status|doctor)
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "--json --help -h" -- "$cur")
                ;;
            install|remove)
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "--dry-run --yes --help -h" -- "$cur")
                ;;
            restore)
                case "$prev" in
                    --backup-id) return ;;
                esac
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "--backup-id --dry-run --yes --help -h" -- "$cur")
                ;;
        esac
        return
    fi

    if [[ "${words[1]:-}" == "onboard" || "${words[1]:-}" == "setup" ]]; then
        case "$prev" in
            --host)
                local host_choices="$onboard_hosts"
                [[ "${words[1]:-}" == setup ]] && host_choices="$setup_hosts"
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "$host_choices" -- "$cur")
                return
                ;;
            --project)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -d -- "$cur")
                return
                ;;
            --runtime)
                if [[ "${words[1]:-}" == "setup" ]]; then
                    COMPREPLY=()
                    while IFS= read -r candidate; do
                        COMPREPLY+=("$candidate")
                    done < <(compgen -W "$runtime_policies" -- "$cur")
                    return
                fi
                ;;
        esac

        COMPREPLY=()
        if [[ "${words[1]:-}" == "setup" ]]; then
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$setup_opts" -- "$cur")
        else
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$onboard_opts" -- "$cur")
        fi
        return
    fi

    if [[ "${words[1]:-}" == "launch" ]]; then
        case "$prev" in
            --project)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -d -- "$cur")
                return
                ;;
            --policy)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "medium high critical" -- "$cur")
                return
                ;;
            --runtime)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "$runtime_policies" -- "$cur")
                return
                ;;
        esac

        COMPREPLY=()
        if [[ "$cword" -eq 2 ]]; then
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$onboard_hosts" -- "$cur")
        else
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$launch_opts" -- "$cur")
        fi
        return
    fi

    if [[ "${words[1]:-}" == "work" ]]; then
        case "$prev" in
            --project)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -d -- "$cur")
                return
                ;;
            --format)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "prompt json" -- "$cur")
                return
                ;;
            --tokens)
                COMPREPLY=()
                return
                ;;
        esac

        COMPREPLY=()
        while IFS= read -r candidate; do
            COMPREPLY+=("$candidate")
        done < <(compgen -W "$work_opts" -- "$cur")
        return
    fi

    # Project-scoped AWM is the agent-facing golden path. Complete its nested
    # actions and values before the generic previous-word dispatch below.
    if [[ "${words[1]:-}" == "awm" && "${words[2]:-}" == "project" ]]; then
        local awm_project_action="${words[3]:-}"

        if [[ "$cword" -eq 3 ]]; then
            COMPREPLY=()
            while IFS= read -r candidate; do
                COMPREPLY+=("$candidate")
            done < <(compgen -W "$awm_project_actions" -- "$cur")
            return
        fi

        case "$prev" in
            --project)
                compopt -o dirnames 2>/dev/null || true
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -d -- "$cur")
                return
                ;;
            --importance)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "critical high normal low" -- "$cur")
                return
                ;;
            --format)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "json prompt" -- "$cur")
                return
                ;;
            --kind)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "discovery checkpoint log mixed" -- "$cur")
                return
                ;;
            --include)
                COMPREPLY=()
                while IFS= read -r candidate; do
                    COMPREPLY+=("$candidate")
                done < <(compgen -W "discoveries,progress,checkpoints,logs" -- "$cur")
                return
                ;;
            --name|--tags|--ttl|--tokens|--limit)
                COMPREPLY=()
                return
                ;;
        esac

        local awm_project_opts=""
        case "$awm_project_action" in
            ensure)
                awm_project_opts="--project --discover-root --name"
                ;;
            session|status|get|progress|close)
                awm_project_opts="--project --discover-root"
                ;;
            checkpoint)
                awm_project_opts="--project --discover-root --importance --tags --ttl"
                ;;
            discovery)
                awm_project_opts="--project --discover-root --importance --tags"
                ;;
            summary)
                awm_project_opts="--project --discover-root --tokens"
                ;;
            context)
                awm_project_opts="--project --discover-root --tokens --format --include"
                ;;
            find)
                awm_project_opts="--project --discover-root --kind --limit"
                ;;
            handoff)
                awm_project_opts="--project --discover-root --tokens --format"
                if [[ "$cword" -eq 4 ]]; then
                    awm_project_opts="prepare $awm_project_opts"
                fi
                ;;
            *)
                COMPREPLY=()
                return
                ;;
        esac

        COMPREPLY=()
        while IFS= read -r candidate; do
            COMPREPLY+=("$candidate")
        done < <(compgen -W "$awm_project_opts" -- "$cur")
        return
    fi

    case "$prev" in
        mainframe)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            return
            ;;

        search|find|grep|help|info|describe)
            # Complete with function names from FUNCTIONS.json if available
            local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
            local json_file="${mainframe_root}/FUNCTIONS.json"

            if [[ -f "$json_file" ]] && command -v jq &>/dev/null; then
                local funcs
                funcs=$(jq -r '.libraries[].functions | keys[]' "$json_file" 2>/dev/null | head -100)
                COMPREPLY=($(compgen -W "$funcs" -- "$cur"))
            fi
            return
            ;;

        quickref|qr|signatures|sigs)
            # Complete with library names or options
            local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
            local lib_dir="${mainframe_root}/lib"
            local libs=""

            # Get library names from lib/*.sh files
            if [[ -d "$lib_dir" ]]; then
                for f in "$lib_dir"/*.sh; do
                    [[ -f "$f" ]] || continue
                    local name
                    name=$(basename "$f" .sh)
                    [[ "$name" == "common" ]] && continue
                    libs="$libs $name"
                done
            fi

            COMPREPLY=($(compgen -W "$quickref_opts $libs" -- "$cur"))
            return
            ;;

        awm)
            COMPREPLY=($(compgen -W "$awm_commands" -- "$cur"))
            return
            ;;

        handoff)
            if [[ "${words[1]:-}" == "awm" ]]; then
                COMPREPLY=($(compgen -W "prepare accept" -- "$cur"))
                return
            fi
            ;;

        protect)
            COMPREPLY=($(compgen -W "status" -- "$cur"))
            return
            ;;

        --search|-s)
            # After --search, complete with function names
            local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
            local json_file="${mainframe_root}/FUNCTIONS.json"

            if [[ -f "$json_file" ]] && command -v jq &>/dev/null; then
                local funcs
                funcs=$(jq -r '.libraries[].functions | keys[]' "$json_file" 2>/dev/null | head -100)
                COMPREPLY=($(compgen -W "$funcs" -- "$cur"))
            fi
            return
            ;;

        version|-v|--version|functions|funcs|list|count|explore|tui|doctor|check|health|benchmark|bench|test|tests|update)
            # These commands take no arguments
            return
            ;;

        --list|-l|--all|-a|--json|-j)
            # These options take no arguments
            return
            ;;
    esac

    # Default: complete with commands
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
}

# Register the completion function
complete -F _mainframe_completions mainframe

# vim: ft=bash

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
    local cur prev words cword

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

    # Top-level commands (including aliases)
    local commands="help version functions funcs list search find grep count quickref qr signatures sigs doctor check health benchmark bench test tests update upgrade"

    # Quickref options
    local quickref_opts="--list -l --all -a --search -s --json -j"

    case "$prev" in
        mainframe)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            return
            ;;

        search|find|grep)
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

        help|-h|--help|version|-v|--version|functions|funcs|list|count|doctor|check|health|benchmark|bench|test|tests|update|upgrade)
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

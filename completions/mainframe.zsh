#compdef mainframe
# =============================================================================
# MAINFRAME Zsh Completion
# =============================================================================
# Install:
#   source /path/to/mainframe/completions/mainframe.zsh
#
# Or add to ~/.zshrc:
#   fpath=("${MAINFRAME_ROOT:-$HOME/.mainframe}/completions" $fpath)
#   autoload -Uz compinit && compinit
#
# Or for Oh My Zsh, copy to custom completions:
#   cp completions/mainframe.zsh ~/.oh-my-zsh/completions/_mainframe
# =============================================================================

_mainframe_get_libraries() {
    local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
    local lib_dir="${mainframe_root}/lib"
    local libs=()

    if [[ -d "$lib_dir" ]]; then
        for f in "$lib_dir"/*.sh(N); do
            [[ -f "$f" ]] || continue
            local name="${f:t:r}"
            [[ "$name" == "common" ]] && continue
            libs+=("$name")
        done
    fi

    echo "${libs[@]}"
}

_mainframe_get_functions() {
    local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
    local json_file="${mainframe_root}/FUNCTIONS.json"

    if [[ -f "$json_file" ]] && (( $+commands[jq] )); then
        jq -r '.libraries[].functions | keys[]' "$json_file" 2>/dev/null | head -100
    fi
}

_mainframe() {
    local -a commands
    local -a quickref_opts
    local -a libs

    commands=(
        'help:Show help message'
        'version:Show MAINFRAME version and environment info'
        'functions:List all available functions'
        'funcs:Alias for functions'
        'list:Alias for functions'
        'search:Search functions by name pattern'
        'find:Alias for search'
        'grep:Alias for search'
        'count:Count total functions available'
        'quickref:Show compact function signatures'
        'qr:Alias for quickref'
        'signatures:Alias for quickref'
        'sigs:Alias for quickref'
        'doctor:Check MAINFRAME installation health'
        'check:Alias for doctor'
        'health:Alias for doctor'
        'benchmark:Run performance benchmarks'
        'bench:Alias for benchmark'
        'test:Run test suite'
        'tests:Alias for test'
        'update:Update MAINFRAME (git-based installations)'
        'upgrade:Alias for update'
    )

    quickref_opts=(
        '--list:List available libraries'
        '-l:List available libraries'
        '--all:Show all functions'
        '-a:Show all functions'
        '--search:Search all functions'
        '-s:Search all functions'
        '--json:Output FUNCTIONS.json path'
        '-j:Output FUNCTIONS.json path'
    )

    case "$words[2]" in
        search|find|grep)
            local -a funcs
            funcs=(${(f)"$(_mainframe_get_functions)"})
            _describe -t functions 'function' funcs
            return
            ;;

        quickref|qr|signatures|sigs)
            case "$words[3]" in
                --search|-s)
                    local -a funcs
                    funcs=(${(f)"$(_mainframe_get_functions)"})
                    _describe -t functions 'function' funcs
                    return
                    ;;
                --list|-l|--all|-a|--json|-j)
                    return
                    ;;
            esac

            # Complete with options or library names
            local -a libs_arr
            libs_arr=(${(f)"$(_mainframe_get_libraries)"})

            _alternative \
                'options:quickref option:((${(kv)quickref_opts[@]}))' \
                'libraries:library:compadd -a libs_arr'
            return
            ;;

        help|version|functions|funcs|list|count|doctor|check|health|benchmark|bench|test|tests|update|upgrade)
            # These commands take no arguments
            return
            ;;
    esac

    # Default: complete with commands
    _describe -t commands 'mainframe command' commands
}

# Register the completion function
compdef _mainframe mainframe

# vim: ft=zsh

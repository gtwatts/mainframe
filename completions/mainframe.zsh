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

_mainframe_get_canonical_invocations() {
    local mainframe_root="${MAINFRAME_ROOT:-$HOME/.mainframe}"
    local manifest_file="${mainframe_root}/MANIFEST.json"

    if [[ -f "$manifest_file" ]] && (( $+commands[jq] )); then
        jq -r '
            .exports | to_entries[] |
            select(.value.contract_status == "reviewed" and
                   (.value.profiles | index("stable-core") != null)) |
            .key
        ' "$manifest_file" 2>/dev/null
    fi
}

_mainframe() {
    local -a commands
    local -a quickref_opts
    local -a awm_commands
    local -a libs

    commands=(
        'version:Show MAINFRAME version and environment info'
        'functions:List all available functions'
        'funcs:Alias for functions'
        'list:Alias for functions'
        'operations:List bundled legacy operation scripts'
        'ops:Alias for operations'
        'run:Run a bundled operation script'
        'invoke:Invoke one reviewed canonical manifest export'
        'code:Use the durable coding control-plane facade'
        'help:Show detailed help for a function'
        'info:Alias for help'
        'describe:Alias for help'
        'search:Search functions by name pattern'
        'find:Alias for search'
        'grep:Alias for search'
        'awm:Manage Agent Working Memory sessions and handoffs'
        'work:Build a bounded read-only brief from existing project memory'
        'count:Count total functions available'
        'quickref:Show compact function signatures'
        'qr:Alias for quickref'
        'signatures:Alias for quickref'
        'sigs:Alias for quickref'
        'fzf:Browse functions interactively with fzf'
        'fuzzy:Alias for fzf'
        'browse:Alias for fzf'
        'explore:Browse functions in a terminal UI'
        'tui:Alias for explore'
        'doctor:Check MAINFRAME installation health'
        'check:Alias for doctor'
        'health:Alias for doctor'
        'shell:Inspect or explicitly repair Bash/zsh integration identity'
        'agent-hook:Enforce shell policy as an AI host pre-tool hook'
        'agent-gateway:Alias for agent-hook'
        'protect:Inspect project host-hook enforcement readiness'
        'host:Inspect, acquire, and manage private coding-agent host runtimes'
        'pi:Inspect, install, or remove the native Pi package integration'
        'control-plane:Operate durable runs, calls, approvals, and evidence'
        'claim:Verify the evidence-bound control-plane promotion claim'
        'setup:Discover local shells and hosts or onboard one explicit host'
        'onboard:Safely configure and verify MAINFRAME for a coding-agent host'
        'launch:Preflight and start one onboarded coding-agent host'
        'activate:Activate MAINFRAME for an AI host'
        'deactivate:Remove MAINFRAME-managed activation content'
        'benchmark:Run performance benchmarks'
        'bench:Alias for benchmark'
        'test:Run test suite'
        'tests:Alias for test'
        'update:Update MAINFRAME (git-based installations)'
        'upgrade:Install an explicitly selected verified release archive'
        'release:Report checked-in release readiness offline'
        'uninstall:Run the installation-owned recoverable uninstaller'
        'new:Create a new agent, tool, workflow, or library'
        'init:Initialize MAINFRAME in the current directory'
        'build:Build static binaries, bundles, or containers'
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

    awm_commands=(
        'project:Use one private AWM session mapped to the physical project'
        'init:Create a private AWM session'
        'resume:Resume an existing session'
        'checkpoint:Save durable key/value state'
        'discovery:Record a high-signal finding'
        'progress:Record task progress'
        'get:Retrieve checkpointed state'
        'summary:Show a structured session summary'
        'context:Build task-specific context'
        'find:Search session material'
        'handoff:Prepare or accept an agent handoff'
        'list:List sessions'
        'status:Show session status'
        'doctor:Diagnose layout and privacy'
        'export:Export a session as Markdown'
        'inspect:Inspect session state'
        'migrate:Upgrade an older session'
    )

    case "$words[2]" in
        shell)
            if (( CURRENT == 3 )); then
                local -a shell_actions
                shell_actions=(
                    'status:Compare selected CLI, inherited root, and managed profiles'
                    'repair:Rewrite only MAINFRAME-managed profile blocks'
                )
                _describe -t shell-actions 'shell action' shell_actions
                return
            fi
            case "${words[CURRENT-1]:-}" in
                --shell)
                    _values 'shell scope' bash zsh all
                    return
                    ;;
            esac
            if [[ "${words[3]:-}" == status ]]; then
                _arguments \
                    '*--shell[shell scope]:scope:(bash zsh all)' \
                    '*--zdotdir[explicit zsh startup directory]:directory:_directories' \
                    '(- *)--json[closed JSON status output]' \
                    '(-h --help)'{-h,--help}'[show shell lifecycle help]'
            elif [[ "${words[3]:-}" == repair ]]; then
                _arguments \
                    '*--shell[shell scope]:scope:(bash zsh all)' \
                    '*--zdotdir[explicit zsh startup directory]:directory:_directories' \
                    '(- *)--dry-run[preview without changing profiles]' \
                    '(- *)--yes[apply the reviewed repair]' \
                    '(-h --help)'{-h,--help}'[show shell lifecycle help]'
            fi
            return
            ;;

        invoke)
            local -a canonical_ids
            canonical_ids=(${(f)"$(_mainframe_get_canonical_invocations)"})
            if (( CURRENT == 3 )); then
                _describe -t canonical-invocations 'canonical ID' canonical_ids
                return
            fi
            _arguments \
                '*--input-json[closed JSON input object or - for stdin]:JSON object:' \
                '*--profile[required manifest profile]:profile:(stable-core)' \
                '*--format[result format]:format:(raw broker-json-v1)' \
                '*--caller[audit-only adapter label]:caller:' \
                '(-h --help)'{-h,--help}'[show canonical invocation help]'
            return
            ;;

        code)
            if (( CURRENT == 3 )); then
                local -a code_actions
                code_actions=(
                    'read:Read a workspace-relative file through the durable control plane'
                    'search:Search workspace-relative text through the durable control plane'
                    'edit:Request an approval-gated atomic edit using stdin content'
                    'test:Request an approval-gated reviewed test run'
                    'build:Request an approval-gated reviewed build'
                    'help:Show durable coding facade help'
                    '--help:Show durable coding facade help'
                    '-h:Show durable coding facade help'
                )
                _describe -t code-actions 'coding action' code_actions
                return
            fi
            case "${words[3]:-}" in
                read|search)
                    _values 'coding option' \
                        '--json[durable structured control-plane result]' \
                        '--[end option parsing]'
                    ;;
                edit)
                    _values 'coding option' \
                        '--preimage-sha256[exact lowercase SHA-256 preimage digest]' \
                        '--[end option parsing]'
                    ;;
            esac
            return
            ;;

        claim)
            _arguments \
                '(- *)--json[closed JSON claim-check result]' \
                '(-h --help)'{-h,--help}'[show claim-check help]'
            return
            ;;

        search|find|grep|help|info|describe)
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

        awm)
            if [[ "${words[3]:-}" == "project" ]]; then
                local -a awm_project_actions
                local awm_project_action="${words[4]:-}"
                awm_project_actions=(
                    'ensure:Create or resume the private project session'
                    'session:Print the existing project session ID without creating it'
                    'status:Inspect the existing project mapping without creating it'
                    'checkpoint:Save durable project state'
                    'get:Retrieve a project checkpoint'
                    'discovery:Record a high-signal project finding'
                    'progress:Record meaningful project progress'
                    'summary:Build a bounded project recap'
                    'context:Build bounded task-specific project context'
                    'find:Search project memory'
                    'handoff:Prepare a bounded project handoff'
                    'close:Complete the active project memory session'
                )

                if [[ $CURRENT -eq 4 ]]; then
                    _describe -t awm-project-actions 'project AWM action' awm_project_actions
                    return
                fi

                case "${words[CURRENT-1]:-}" in
                    --project)
                        _directories
                        return
                        ;;
                    --importance)
                        _values 'importance' critical high normal low
                        return
                        ;;
                    --format)
                        _values 'output format' json prompt
                        return
                        ;;
                    --kind)
                        _values 'search kind' discovery checkpoint log mixed
                        return
                        ;;
                    --include)
                        _values 'context sections' discoveries,progress,checkpoints,logs
                        return
                        ;;
                    --name|--tags|--ttl|--tokens|--limit)
                        return
                        ;;
                esac

                case "$awm_project_action" in
                    ensure)
                        _values 'project AWM option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--name[human-readable session name]'
                        ;;
                    session|status|get|progress|close)
                        _values 'project AWM option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]'
                        ;;
                    checkpoint)
                        _values 'project checkpoint option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--importance[durability importance]' \
                            '--tags[comma-separated tags]' \
                            '--ttl[checkpoint lifetime in seconds]'
                        ;;
                    discovery)
                        _values 'project discovery option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--importance[durability importance]' \
                            '--tags[comma-separated tags]'
                        ;;
                    summary)
                        _values 'project summary option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--tokens[complete-document token budget]'
                        ;;
                    context)
                        _values 'project context option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--tokens[complete-document token budget]' \
                            '--format[output format]' \
                            '--include[context sections]'
                        ;;
                    find)
                        _values 'project search option' \
                            '--project[exact physical project directory]' \
                            '--discover-root[resolve the managed project or Git worktree root]' \
                            '--kind[result kind]' \
                            '--limit[maximum results]'
                        ;;
                    handoff)
                        if [[ $CURRENT -eq 5 ]]; then
                            _values 'project handoff action or option' \
                                'prepare[prepare a bounded handoff]' \
                                '--project[exact physical project directory]' \
                                '--discover-root[resolve the managed project or Git worktree root]' \
                                '--tokens[complete-document token budget]' \
                                '--format[output format]'
                        else
                            _values 'project handoff option' \
                                '--project[exact physical project directory]' \
                                '--discover-root[resolve the managed project or Git worktree root]' \
                                '--tokens[complete-document token budget]' \
                                '--format[output format]'
                        fi
                        ;;
                esac
            elif [[ "${words[3]:-}" == "handoff" && $CURRENT -eq 4 ]]; then
                _values 'handoff action' prepare accept
            elif [[ $CURRENT -eq 3 ]]; then
                _describe -t awm-commands 'AWM command' awm_commands
            fi
            return
            ;;

        protect)
            _values 'protect command' status
            return
            ;;

        host)
            case "${words[3]:-}" in
                status)
                    _arguments \
                        '1:command:(host)' \
                        '2:action:(status)' \
                        '3:host:(codex claude-code copilot gemini)' \
                        '--runtime[runtime selection policy]:runtime:(auto managed system)' \
                        '--json[emit path-redacted JSON status]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                install)
                    _arguments \
                        '1:command:(host)' \
                        '2:action:(install)' \
                        '3:host:(codex claude-code copilot)' \
                        '(--package-dir)--download[acquire exact locked packages from the closed registry source]' \
                        '(--download)--package-dir[use a local offline directory containing pinned package archives]:package directory:_directories' \
                        '(--yes)--dry-run[acquire and verify without publishing a managed host]' \
                        '(--dry-run)--yes[confirm publishing the verified managed host]' \
                        '--json[emit noninteractive path-redacted JSON; actionable requests require --dry-run or --yes]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                remove)
                    _arguments \
                        '1:command:(host)' \
                        '2:action:(remove)' \
                        '3:host:(codex claude-code copilot)' \
                        '(--yes)--dry-run[preview quarantine without changing managed state]' \
                        '(--dry-run)--yes[confirm quarantining the managed host]' \
                        '--json[emit noninteractive path-redacted JSON; actionable requests require --dry-run or --yes]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                restore)
                    _arguments \
                        '1:command:(host)' \
                        '2:action:(restore)' \
                        '3:host:(codex claude-code copilot)' \
                        '--quarantine-id[exact generated removed.<18-hex> quarantine ID]:quarantine ID:' \
                        '(--yes)--dry-run[authenticate exact quarantine generation without restoring it]' \
                        '(--dry-run)--yes[confirm exact authenticated restore]' \
                        '--json[emit noninteractive path-redacted JSON; actionable requests require --dry-run or --yes]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                *)
                    _values 'host action' status install remove restore
                    ;;
            esac
            return
            ;;

        pi)
            case "${words[3]:-}" in
                status)
                    _arguments \
                        '1:command:(pi)' \
                        '2:action:(status)' \
                        '--json[emit machine-readable package and collision status]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                doctor)
                    _arguments \
                        '1:command:(pi)' \
                        '2:action:(doctor)' \
                        '--json[emit machine-readable compatibility and activation diagnosis]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                install)
                    _arguments \
                        '1:command:(pi)' \
                        '2:action:(install)' \
                        '(--yes)--dry-run[preview package activation and legacy quarantine]' \
                        '(--dry-run)--yes[confirm package activation and legacy quarantine]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                remove)
                    _arguments \
                        '1:command:(pi)' \
                        '2:action:(remove)' \
                        '(--yes)--dry-run[preview managed package detachment]' \
                        '(--dry-run)--yes[confirm managed package detachment]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                restore)
                    _arguments \
                        '1:command:(pi)' \
                        '2:action:(restore)' \
                        '--backup-id[exact private migration backup basename]:backup ID:' \
                        '(--yes)--dry-run[authenticate exact recovery without restoring]' \
                        '(--dry-run)--yes[confirm exact pre-install snapshot recovery]' \
                        '(-h --help)'{-h,--help}'[show help]'
                    ;;
                *)
                    _values 'Pi action' \
                        'status[inspect package and legacy collision state]' \
                        'doctor[diagnose exact Pi compatibility and live-activation next steps]' \
                        'install[activate the first-party package and migrate legacy resources]' \
                        'remove[detach the managed package while preserving backups]' \
                        'restore[recover one exact authenticated pre-install migration snapshot]' \
                        'help[show Pi integration help]'
                    ;;
            esac
            return
            ;;

        setup)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '--host[host or Pi package flow to configure]:host:(codex claude-code copilot gemini pi)' \
                '--project[project directory]:project directory:_directories' \
                '--proof[run the hostless zero-residue first-run mechanism proof]' \
                '--runtime[runtime selection policy]:runtime:(auto managed system)' \
                '--dry-run[preview project changes without writing]' \
                '--yes[confirm a reviewed non-interactive onboarding]'
            return
            ;;

        onboard)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '--host[host to configure]:host:(codex claude-code copilot gemini)' \
                '--project[project directory]:project directory:_directories' \
                '--dry-run[preview project changes without writing]' \
                '--yes[confirm a reviewed non-interactive onboarding]'
            return
            ;;

        launch)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '1:host:(codex claude-code copilot gemini)' \
                '--project[onboarded project directory]:project directory:_directories' \
                '--policy[gateway block tier]:policy:(medium high critical)' \
                '--runtime[runtime selection policy]:runtime:(auto managed system)' \
                '--dry-run[verify readiness without starting the host]'
            return
            ;;

        work)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '1:task:' \
                '--project[project or nested directory]:project directory:_directories' \
                '--tokens[memory-context token budget (128-4000)]:token budget:' \
                '--format[output format]:format:(prompt json)'
            return
            ;;

        upgrade)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '--version[exact stable release version]:version:' \
                '--allow-downgrade[permit an explicit downgrade]' \
                '--dry-run[verify and stage without replacing the runtime]' \
                '--confirm-agents-stopped[confirm no agents are using the install]' \
                '--recover[recover an interrupted transaction]' \
                '--journal[exact recovery journal]:journal file:_files'
            return
            ;;

        release)
            if (( CURRENT == 3 )); then
                _values 'release action' \
                    'readiness:Inspect offline release readiness' \
                    'help:Show release readiness help'
            elif [[ "${words[3]:-}" == readiness ]]; then
                _arguments \
                    '(-h --help)'{-h,--help}'[show help]' \
                    '--json[emit one machine-readable readiness object]'
            fi
            return
            ;;

        control-plane)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '--ledger[owner-private JSONL ledger]:ledger file:_files' \
                '1:control-plane command:(run-create run-transition call-create call-request-approval approval-grant approval-consume trace-execute disposable-write-execute show)'
            return
            ;;

        uninstall)
            _arguments \
                '(-h --help)'{-h,--help}'[show help]' \
                '--dry-run[print intended changes without modifying anything]' \
                '--purge[delete verified runtime files and preserve other in-root data]' \
                '--purge-state[with --purge, delete all in-root data]' \
                '--dir[installation directory]:installation directory:_directories' \
                '--bin[CLI link directory]:CLI link directory:_directories' \
                '--shell-config[shell profile to inspect]:shell profile:_files'
            return
            ;;

        version|functions|funcs|list|count|explore|tui|doctor|check|health|benchmark|bench|test|tests|update)
            # These commands take no arguments
            return
            ;;
    esac

    # Default: complete with commands
    _describe -t commands 'mainframe command' commands
}

# The installer sources this file directly. A fresh zsh has not necessarily
# initialized its completion system yet, so make compdef available first.
if (( ! $+functions[compdef] )); then
    autoload -Uz compinit && compinit
fi

# Register the completion function when completion initialization succeeded.
if (( $+functions[compdef] )); then
    compdef _mainframe mainframe
fi

# vim: ft=zsh

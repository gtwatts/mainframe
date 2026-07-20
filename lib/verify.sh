#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2119,SC2120,SC2016,SC1003,SC2155,SC2181,SC2059,SC2206

# =============================================================================
# MAINFRAME/lib/verify.sh - Command Verification Engine (CVE V10)
# =============================================================================
# Description: Static analysis and validation for bash commands without
#              execution. Detects errors, typos, dangerous patterns, and
#              estimates resource usage.
#
# Version: 1.0.0
# Requires: Bash 4.0+
# Standards: USOP (Universal Structured Output Protocol)
# =============================================================================
# "Verify before you execute - the mainframe way."
# =============================================================================
#
# PUBLIC API:
#
#   verify_command "cmd_string"
#     Returns JSON: {valid: bool, issues: [], suggestions: [], meta: {}}
#     Checks for: typos, dangerous patterns, undefined variables, 
#                 command existence, style issues
#
#   verify_pipeline "cmd1 | cmd2"
#     Returns JSON with pipeline-specific validation
#     Checks for: useless cat, multiple greps, data flow compatibility
#
#   verify_estimate "cmd"
#     Returns JSON: {estimates: {time_s, memory_mb, confidence}, meta: {}}
#     Predicts resource usage based on command profiles
#
#   verify_suggest_fix "error_output"
#     Returns JSON: {fixes: [], confidence, meta: {}}
#     Suggests fixes based on error patterns
#
#   verify_and_heal "cmd"
#     Returns JSON: {valid, original, healed, issues, meta: {}}
#     Verifies and returns auto-healed version of command
#
# EXAMPLE USAGE:
#
#   source ~/.mainframe/lib/verify.sh
#
#   # Check for typos
#   result=$(verify_command "sl -la")
#   # Returns: {"valid":false,"issues":[{"type":"typo",...}],...}
#
#   # Validate pipeline
#   result=$(verify_pipeline "cat file.txt | grep foo | wc -l")
#   # Returns: {"valid":true,"issues":[{"type":"style","msg":"Useless use of cat"}],...}
#
#   # Estimate resources
#   result=$(verify_estimate "find / -name '*.txt'")
#   # Returns: {"estimates":{"time_s":1.0,"memory_mb":10,"confidence":"low"},...}
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_VERIFY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_VERIFY_LOADED=1

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly VERIFY_VERSION="1.0.0"
readonly VERIFY_SCHEMA_VERSION="1.0"

# Verification severity levels
readonly VERIFY_SEVERITY_CRITICAL="critical"
readonly VERIFY_SEVERITY_ERROR="error"
readonly VERIFY_SEVERITY_WARNING="warning"
readonly VERIFY_SEVERITY_STYLE="style"
readonly VERIFY_SEVERITY_INFO="info"

# Issue types
readonly VERIFY_TYPE_DANGEROUS="dangerous"
readonly VERIFY_TYPE_TYPO="typo"
readonly VERIFY_TYPE_UNDEFINED="undefined"
readonly VERIFY_TYPE_UNQUOTED="unquoted"
readonly VERIFY_TYPE_DEPRECATED="deprecated"
readonly VERIFY_TYPE_STYLE="style"
readonly VERIFY_TYPE_PERFORMANCE="performance"
readonly VERIFY_TYPE_SYNTAX="syntax"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_verify_log() {
    local level="$1"
    shift
    if declare -F _mainframe_log &>/dev/null; then
        _mainframe_log "verify" "$level" "$*"
    elif [[ "${MAINFRAME_QUIET:-}" != "1" && "${MAINFRAME_DEBUG:-}" == "1" ]]; then
        printf '[verify] %s: %s\n' "$level" "$*" >&2
    fi
}

_verify_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    str="${str//[^[:print:][:space:]]/}"
    printf '%s' "$str"
}

_verify_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local epoch_real="$EPOCHREALTIME"
        local seconds="${epoch_real%%.*}"
        local frac="${epoch_real#*.}"
        frac="${frac}000"
        printf '%s%s' "$seconds" "${frac:0:3}"
    else
        local ns
        ns=$(date +%s%N 2>/dev/null)
        if [[ "$ns" =~ ^[0-9]+$ && ${#ns} -gt 6 ]]; then
            printf '%s' "${ns:0:${#ns}-6}"
        else
            printf '%s000' "${EPOCHSECONDS:-$(date +%s)}"
        fi
    fi
}

# Build issue object
_verify_build_issue() {
    local type="$1"
    local severity="$2"
    local msg="$3"
    printf '{"type":"%s","severity":"%s","msg":"%s"}' \
        "$type" "$severity" "$(_verify_json_escape "$msg")"
}

# Extract command name from command string
_verify_extract_cmd() {
    local cmd="$1"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    printf '%s' "${cmd%%[[:space:]]*}"
}

# Check if command exists in PATH
_verify_cmd_exists() {
    local cmd="$1"
    case "$cmd" in
        cd|echo|printf|pwd|source|.|exit|export|unset|alias|unalias|type|builtin|command|shift|return|break|continue|exec|eval|set|shopt|trap|umask|wait|times|read|readonly|local|declare|typeset|enable|help|logout|dirs|pushd|popd|history|suspend|disown|jobs|fg|bg|kill|ulimit|hash|test|\[|false|true|shopt|caller|mapfile|readarray)
            return 0
            ;;
    esac
    command -v "$cmd" &>/dev/null
}

# =============================================================================
# TYPO CHECKING
# =============================================================================

_verify_check_typos() {
    local cmd="$1"
    local first_word
    first_word=$(_verify_extract_cmd "$cmd")
    
    case "$first_word" in
        sl) echo "$(_verify_build_issue typo error "Possible typo: 'sl' -> did you mean 'ls'?")" ;;
        ks) echo "$(_verify_build_issue typo error "Possible typo: 'ks' -> did you mean 'ls'?")" ;;
        gti) echo "$(_verify_build_issue typo error "Possible typo: 'gti' -> did you mean 'git'?")" ;;
        gir) echo "$(_verify_build_issue typo error "Possible typo: 'gir' -> did you mean 'git'?")" ;;
        mav) echo "$(_verify_build_issue typo error "Possible typo: 'mav' -> did you mean 'mv'?")" ;;
        vm) echo "$(_verify_build_issue typo error "Possible typo: 'vm' -> did you mean 'mv'?")" ;;
        graep) echo "$(_verify_build_issue typo error "Possible typo: 'graep' -> did you mean 'grep'?")" ;;
        grp) echo "$(_verify_build_issue typo error "Possible typo: 'grp' -> did you mean 'grep'?")" ;;
        gerp) echo "$(_verify_build_issue typo error "Possible typo: 'gerp' -> did you mean 'grep'?")" ;;
        grpe) echo "$(_verify_build_issue typo error "Possible typo: 'grpe' -> did you mean 'grep'?")" ;;
        mikdir) echo "$(_verify_build_issue typo error "Possible typo: 'mikdir' -> did you mean 'mkdir'?")" ;;
        mkdri) echo "$(_verify_build_issue typo error "Possible typo: 'mkdri' -> did you mean 'mkdir'?")" ;;
        touc) echo "$(_verify_build_issue typo error "Possible typo: 'touc' -> did you mean 'touch'?")" ;;
        tuch) echo "$(_verify_build_issue typo error "Possible typo: 'tuch' -> did you mean 'touch'?")" ;;
        chmd) echo "$(_verify_build_issue typo error "Possible typo: 'chmd' -> did you mean 'chmod'?")" ;;
        chomd) echo "$(_verify_build_issue typo error "Possible typo: 'chomd' -> did you mean 'chmod'?")" ;;
        chwon) echo "$(_verify_build_issue typo error "Possible typo: 'chwon' -> did you mean 'chown'?")" ;;
        pyhton) echo "$(_verify_build_issue typo error "Possible typo: 'pyhton' -> did you mean 'python'?")" ;;
        pyton) echo "$(_verify_build_issue typo error "Possible typo: 'pyton' -> did you mean 'python'?")" ;;
        piton) echo "$(_verify_build_issue typo error "Possible typo: 'piton' -> did you mean 'python'?")" ;;
        doker) echo "$(_verify_build_issue typo error "Possible typo: 'doker' -> did you mean 'docker'?")" ;;
        dcoker) echo "$(_verify_build_issue typo error "Possible typo: 'dcoker' -> did you mean 'docker'?")" ;;
        sduo) echo "$(_verify_build_issue typo error "Possible typo: 'sduo' -> did you mean 'sudo'?")" ;;
        suso) echo "$(_verify_build_issue typo error "Possible typo: 'suso' -> did you mean 'sudo'?")" ;;
        sudp) echo "$(_verify_build_issue typo error "Possible typo: 'sudp' -> did you mean 'sudo'?")" ;;
        eho) echo "$(_verify_build_issue typo error "Possible typo: 'eho' -> did you mean 'echo'?")" ;;
        ecoh) echo "$(_verify_build_issue typo error "Possible typo: 'ecoh' -> did you mean 'echo'?")" ;;
        ehco) echo "$(_verify_build_issue typo error "Possible typo: 'ehco' -> did you mean 'echo'?")" ;;
        exot) echo "$(_verify_build_issue typo error "Possible typo: 'exot' -> did you mean 'exit'?")" ;;
        exti) echo "$(_verify_build_issue typo error "Possible typo: 'exti' -> did you mean 'exit'?")" ;;
        clera) echo "$(_verify_build_issue typo error "Possible typo: 'clera' -> did you mean 'clear'?")" ;;
        claer) echo "$(_verify_build_issue typo error "Possible typo: 'claer' -> did you mean 'clear'?")" ;;
        cd..) echo "$(_verify_build_issue typo error "Possible typo: 'cd..' -> did you mean 'cd ..'?")" ;;
    esac
}

# =============================================================================
# DANGEROUS PATTERN CHECKS
# =============================================================================

_verify_check_dangerous() {
    local cmd="$1"
    local issues=""
    
    # rm -rf /
    if [[ "$cmd" =~ rm[[:space:]]+-[a-zA-Z]*f[[:space:]]+/(dev/)?([sh]da?[0-9]*)?[[:space:]]*$ ]]; then
        issues="$(_verify_build_issue dangerous critical "rm -rf / detected - will destroy your system")"
    fi
    
    # rm -rf with variable that might be empty
    if [[ "$cmd" =~ rm[[:space:]]+-[a-zA-Z]*f[[:space:]]+.*\$[A-Za-z_] ]]; then
        if [[ ! "$cmd" =~ \[\[.*-n.*\]\].*&&.*rm ]]; then
            issues="${issues:+$issues,}$(_verify_build_issue dangerous critical "rm -rf with variable without guard")"
        fi
    fi
    
    # Fork bomb detection (simplified pattern)
    if [[ "$cmd" == *':(){ :|:& };:'* ]]; then
        issues="${issues:+$issues,}$(_verify_build_issue dangerous critical "Fork bomb detected - do not execute")"
    fi
    
    # Pipe-to-shell: delegate to tirith if available, otherwise use basic regex
    if declare -F tirith_scan_pipe &>/dev/null; then
        # Use comprehensive tirith pipe scanning
        local _verify_prev_count="${#_TIRITH_FINDINGS[@]}"
        tirith_scan_pipe "$cmd" "verify" 2>/dev/null && \
            issues="${issues:+$issues,}$(_verify_build_issue dangerous warning "Pipe-to-shell pattern detected (tirith)")"
    else
        # Fallback: basic curl/wget pipe detection
        if [[ "$cmd" =~ curl.*\|[[:space:]]*bash ]] || [[ "$cmd" =~ curl.*\|.*sh[[:space:]]*$ ]]; then
            issues="${issues:+$issues,}$(_verify_build_issue dangerous warning "Piping curl to shell - download and inspect first")"
        fi

        if [[ "$cmd" =~ wget.*-O-.*\|[[:space:]]*bash ]] || [[ "$cmd" =~ wget.*\|.*sh[[:space:]]*$ ]]; then
            issues="${issues:+$issues,}$(_verify_build_issue dangerous warning "Piping wget to shell - download and inspect first")"
        fi
    fi
    
    # eval with network
    if [[ "$cmd" =~ eval.*\$\(.*curl ]] || [[ "$cmd" =~ eval.*\`.*curl ]]; then
        issues="${issues:+$issues,}$(_verify_build_issue dangerous error "eval with curl output - security risk")"
    fi
    
    printf '%s' "$issues"
}

# =============================================================================
# VARIABLE CHECKS
# =============================================================================

_verify_check_variables() {
    local cmd="$1"
    local issues=""
    
    # Find unquoted variables outside of quotes
    local vars=$(echo "$cmd" | grep -oE '(^|[[:space:]]|;|\\)\$[a-zA-Z_][a-zA-Z0-9_]*([[:space:]]|;|&|\||<|>|$)' 2>/dev/null || true)
    
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        local var_name="${var//[[:space:];|&<>]/}"
        var_name="${var_name#\$}"
        
        # Skip special variables and common env vars
        case "$var_name" in
            _|1|2|3|4|5|6|7|8|9|0|\@|\*|\#|\$|\?|-|HOME|USER|PATH|SHELL|HOSTNAME|PWD|OLDPWD|TERM|LANG|EDITOR|PS1|PS2|UID|EUID|PPID|SSH_CLIENT|SSH_TTY)
                continue
                ;;
            MAINFRAME_*|AMMA_*)
                continue
                ;;
        esac
        
        # Check if variable is set
        if [[ -z "${!var_name:-}" ]]; then
            issues="${issues:+$issues,}$(_verify_build_issue undefined warning "Undefined variable: \$$var_name")"
        fi
    done <<< "$vars"
    
    printf '%s' "$issues"
}

# =============================================================================
# COMMAND EXISTENCE CHECK
# =============================================================================

_verify_check_command_exists() {
    local cmd="$1"
    local cmd_name
    cmd_name=$(_verify_extract_cmd "$cmd")
    
    # Skip special constructs
    [[ "$cmd_name" =~ = ]] && return
    [[ "$cmd_name" == if ]] && return
    [[ "$cmd_name" == then ]] && return
    [[ "$cmd_name" == else ]] && return
    [[ "$cmd_name" == elif ]] && return
    [[ "$cmd_name" == fi ]] && return
    [[ "$cmd_name" == for ]] && return
    [[ "$cmd_name" == while ]] && return
    [[ "$cmd_name" == do ]] && return
    [[ "$cmd_name" == done ]] && return
    [[ "$cmd_name" == case ]] && return
    [[ "$cmd_name" == esac ]] && return
    [[ "$cmd_name" == function ]] && return
    [[ "$cmd_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]] && return
    [[ "$cmd_name" =~ / ]] && return
    
    if ! _verify_cmd_exists "$cmd_name" 2>/dev/null; then
        echo "$(_verify_build_issue syntax error "Command not found: $cmd_name")"
    fi
}

# =============================================================================
# STYLE CHECKS
# =============================================================================

_verify_check_style() {
    local cmd="$1"
    local issues=""
    
    # Backtick command substitution
    if [[ "$cmd" =~ \`[^\`]+\` ]]; then
        issues="$(_verify_build_issue style style "Backtick command substitution - use \$() instead")"
    fi
    
    # echo with flags
    if [[ "$cmd" =~ echo[[:space:]]+-[neE] ]]; then
        issues="${issues:+$issues,}$(_verify_build_issue style style "echo flags are non-portable - use printf instead")"
    fi
    
    printf '%s' "$issues"
}

# =============================================================================
# PIPELINE CHECKS
# =============================================================================

_verify_check_pipeline() {
    local pipeline="$1"
    local issues=""
    
    # Useless use of cat
    if [[ "$pipeline" =~ ^cat[[:space:]]+[^|]+\|.*grep ]]; then
        issues="$(_verify_build_issue style style "Useless use of cat - grep can read files directly")"
    fi
    
    # Multiple greps
    if [[ "$pipeline" =~ grep.*\|.*grep ]]; then
        issues="${issues:+$issues,}$(_verify_build_issue style style "Multiple greps - consider using a single grep with -E")"
    fi
    
    # awk | grep
    if [[ "$pipeline" =~ awk.*\|.*grep ]]; then
        issues="${issues:+$issues,}$(_verify_build_issue style style "grep after awk - awk can filter with /pattern/")"
    fi
    
    printf '%s' "$issues"
}

# =============================================================================
# SUGGESTION GENERATION
# =============================================================================

_verify_generate_suggestion() {
    local cmd="$1"
    local issue_type="$2"
    local issue_msg="$3"
    
    case "$issue_type" in
        typo)
            case "$issue_msg" in
                *sl*'->'*ls*) echo "ls${cmd#sl}" ;;
                *gti*'->'*git*) echo "git${cmd#gti}" ;;
                *gir*'->'*git*) echo "git${cmd#gir}" ;;
                *graep*'->'*grep*) echo "grep${cmd#graep}" ;;
                *grp*'->'*grep*) echo "grep${cmd#grp}" ;;
                *gerp*'->'*grep*) echo "grep${cmd#gerp}" ;;
                *mikdir*'->'*mkdir*) echo "mkdir${cmd#mikdir}" ;;
                *mav*'->'*mv*) echo "mv${cmd#mav}" ;;
                *pyhton*'->'*python*) echo "python${cmd#pyhton}" ;;
                *pyton*'->'*python*) echo "python${cmd#pyton}" ;;
                *doker*'->'*docker*) echo "docker${cmd#doker}" ;;
                *sduo*'->'*sudo*) echo "sudo${cmd#sduo}" ;;
                *eho*'->'*echo*) echo "echo${cmd#eho}" ;;
                *clera*'->'*clear*) echo "clear${cmd#clera}" ;;
                *cd..*'->'*cd*) echo "cd ..${cmd#cd..}" ;;
                *) echo "" ;;
            esac
            ;;
        dangerous)
            if [[ "$issue_msg" =~ rm.*variable ]]; then
                echo 'Add guard: [[ -n "$VAR" ]] && rm -rf "$VAR"'
            else
                echo "Review and use safer alternatives"
            fi
            ;;
        undefined)
            echo "Ensure variable is defined before use"
            ;;
        style)
            if [[ "$issue_msg" =~ cat ]]; then
                local file="${cmd#cat }"
                file="${file%%|*}"
                file="${file#"${file%%[![:space:]]*}"}"
                file="${file%"${file##*[![:space:]]}"}"
                local rest="${cmd#*|}"
                rest="${rest#grep}"
                echo "grep$rest $file"
            else
                echo "Fix style issues for better portability"
            fi
            ;;
        *)
            echo "Review command for correctness"
            ;;
    esac
}

# =============================================================================
# HEAL COMMAND
# =============================================================================

_verify_heal() {
    local cmd="$1"
    local healed="$cmd"
    
    # Fix common typos
    local first_word=$(_verify_extract_cmd "$cmd")
    case "$first_word" in
        sl) healed="ls${cmd#sl}" ;;
        gti) healed="git${cmd#gti}" ;;
        gir) healed="git${cmd#gir}" ;;
        graep) healed="grep${cmd#graep}" ;;
        grp) healed="grep${cmd#grp}" ;;
        gerp) healed="grep${cmd#gerp}" ;;
        grpe) healed="grep${cmd#grpe}" ;;
        mikdir) healed="mkdir${cmd#mikdir}" ;;
        mkdri) healed="mkdir${cmd#mkdri}" ;;
        mav) healed="mv${cmd#mav}" ;;
        vm) healed="mv${cmd#vm}" ;;
        pyhton) healed="python${cmd#pyhton}" ;;
        pyton) healed="python${cmd#pyton}" ;;
        piton) healed="python${cmd#piton}" ;;
        doker) healed="docker${cmd#doker}" ;;
        dcoker) healed="docker${cmd#dcoker}" ;;
        sduo) healed="sudo${cmd#sduo}" ;;
        suso) healed="sudo${cmd#suso}" ;;
        sudp) healed="sudo${cmd#sudp}" ;;
        eho) healed="echo${cmd#eho}" ;;
        ecoh) healed="echo${cmd#ecoh}" ;;
        ehco) healed="echo${cmd#ehco}" ;;
        clera) healed="clear${cmd#clera}" ;;
        claer) healed="clear${cmd#claer}" ;;
        cd..) healed="cd ..${cmd#cd..}" ;;
        touc) healed="touch${cmd#touc}" ;;
        tuch) healed="touch${cmd#tuch}" ;;
        chmd) healed="chmod${cmd#chmd}" ;;
        chomd) healed="chmod${cmd#chomd}" ;;
        chwon) healed="chown${cmd#chwon}" ;;
        exot) healed="exit${cmd#exot}" ;;
        exti) healed="exit${cmd#exti}" ;;
    esac
    
    printf '%s' "$healed"
}

# =============================================================================
# RESOURCE ESTIMATION
# =============================================================================

_verify_estimate_cmd() {
    local cmd="$1"
    local cmd_name=$(_verify_extract_cmd "$cmd")
    
    local time_s="0.1"
    local mem_mb="10"
    local confidence="low"
    
    case "$cmd_name" in
        cat|echo|printf|ls|pwd|cd|mkdir|touch|rm|mv|cp|chmod|chown|grep|cut|wc|head|tail|tr)
            time_s="0.01"
            mem_mb="1"
            confidence="high"
            ;;
        awk|sed)
            time_s="0.1"
            mem_mb="10"
            confidence="medium"
            ;;
        sort|uniq)
            time_s="0.5"
            mem_mb="50"
            confidence="medium"
            ;;
        find)
            time_s="1.0"
            mem_mb="10"
            confidence="low"
            ;;
        tar|gzip|zip)
            time_s="2.0"
            mem_mb="100"
            confidence="medium"
            ;;
        curl|wget)
            time_s="5.0"
            mem_mb="5"
            confidence="low"
            ;;
        git)
            time_s="0.5"
            mem_mb="20"
            confidence="low"
            ;;
        docker)
            time_s="2.0"
            mem_mb="50"
            confidence="low"
            ;;
        python|node|ruby)
            time_s="0.5"
            mem_mb="50"
            confidence="medium"
            ;;
        make)
            time_s="30.0"
            mem_mb="200"
            confidence="low"
            ;;
        rsync)
            time_s="60.0"
            mem_mb="100"
            confidence="low"
            ;;
    esac
    
    printf '{"time_s":%s,"memory_mb":%s,"confidence":"%s"}' "$time_s" "$mem_mb" "$confidence"
}

# =============================================================================
# PUBLIC API
# =============================================================================

verify_command() {
    local start_time=$(_verify_now_ms)
    local cmd="$1"
    
    if [[ -z "$cmd" ]]; then
        printf '{"valid":true,"issues":[],"suggestions":[],"meta":{"elapsed_ms":0,"timestamp":%s}}' "$(_verify_now_ms)"
        return 0
    fi
    
    local all_issues=""
    local all_suggestions=""
    local valid="true"
    
    # Run checks
    local typo_issues=$(_verify_check_typos "$cmd")
    local dangerous_issues=$(_verify_check_dangerous "$cmd")
    local var_issues=$(_verify_check_variables "$cmd")
    local cmd_issues=$(_verify_check_command_exists "$cmd")
    local style_issues=$(_verify_check_style "$cmd")
    
    # Combine issues
    [[ -n "$typo_issues" ]] && all_issues="${all_issues:+$all_issues,}$typo_issues"
    [[ -n "$dangerous_issues" ]] && all_issues="${all_issues:+$all_issues,}$dangerous_issues"
    [[ -n "$var_issues" ]] && all_issues="${all_issues:+$all_issues,}$var_issues"
    [[ -n "$cmd_issues" ]] && all_issues="${all_issues:+$all_issues,}$cmd_issues"
    [[ -n "$style_issues" ]] && all_issues="${all_issues:+$all_issues,}$style_issues"
    
    # Determine validity
    if [[ "$all_issues" =~ \"severity\":\"critical\" ]] || [[ "$all_issues" =~ \"severity\":\"error\" ]]; then
        valid="false"
    fi
    
    # Generate suggestions
    if [[ -n "$typo_issues" ]]; then
        local suggestion=$(_verify_generate_suggestion "$cmd" "typo" "$typo_issues")
        [[ -n "$suggestion" ]] && all_suggestions="${all_suggestions:+$all_suggestions,}\"$(_verify_json_escape "$suggestion")\""
    fi
    if [[ -n "$dangerous_issues" ]]; then
        local suggestion=$(_verify_generate_suggestion "$cmd" "dangerous" "$dangerous_issues")
        [[ -n "$suggestion" ]] && all_suggestions="${all_suggestions:+$all_suggestions,}\"$(_verify_json_escape "$suggestion")\""
    fi
    if [[ -n "$var_issues" ]]; then
        local suggestion=$(_verify_generate_suggestion "$cmd" "undefined" "$var_issues")
        [[ -n "$suggestion" ]] && all_suggestions="${all_suggestions:+$all_suggestions,}\"$(_verify_json_escape "$suggestion")\""
    fi
    if [[ -n "$style_issues" ]]; then
        local suggestion=$(_verify_generate_suggestion "$cmd" "style" "$style_issues")
        [[ -n "$suggestion" ]] && all_suggestions="${all_suggestions:+$all_suggestions,}\"$(_verify_json_escape "$suggestion")\""
    fi
    
    local elapsed=$(( $(_verify_now_ms) - start_time ))
    
    printf '{"valid":%s,"issues":[%s],"suggestions":[%s],"meta":{"elapsed_ms":%s,"timestamp":%s}}' \
        "$valid" "$all_issues" "$all_suggestions" "$elapsed" "$(_verify_now_ms)"
}

verify_pipeline() {
    local start_time=$(_verify_now_ms)
    local pipeline="$1"
    
    if [[ -z "$pipeline" ]]; then
        printf '{"valid":true,"issues":[],"suggestions":[],"meta":{"elapsed_ms":0,"timestamp":%s}}' "$(_verify_now_ms)"
        return 0
    fi
    
    # If not a pipeline, delegate to verify_command
    if [[ ! "$pipeline" =~ \| ]]; then
        verify_command "$pipeline"
        return
    fi
    
    local all_issues=""
    local all_suggestions=""
    local valid="true"
    local stage_count=0
    
    # Count stages
    stage_count=$(echo "$pipeline" | tr -cd '|' | wc -c)
    stage_count=$((stage_count + 1))
    
    # Check each stage
    local IFS='|'
    for stage in $pipeline; do
        stage="${stage#"${stage%%[![:space:]]*}"}"
        stage="${stage%"${stage##*[![:space:]]}"}"
        
        local stage_result=$(verify_command "$stage")
        # Extract issues array more carefully - look for "issues":[...]
        local stage_issues=$(echo "$stage_result" | sed -n 's/.*"issues":\[\([^]]*\)\].*/\1/p' | head -1)
        
        if [[ -n "$stage_issues" ]]; then
            all_issues="${all_issues:+$all_issues,}$stage_issues"
        fi
    done
    
    # Pipeline-specific checks
    local pipe_issues=$(_verify_check_pipeline "$pipeline")
    [[ -n "$pipe_issues" ]] && all_issues="${all_issues:+$all_issues,}$pipe_issues"
    
    # Generate suggestions
    if [[ "$pipeline" =~ ^cat[[:space:]]+[^|]+\|.*grep ]]; then
        local file="${pipeline#cat }"
        file="${file%%|*}"
        file="${file#"${file%%[![:space:]]*}"}"
        file="${file%"${file##*[![:space:]]}"}"
        all_suggestions="${all_suggestions:+$all_suggestions,}\"Pass $file as argument to grep instead of using cat\""
    fi
    
    if [[ "$pipeline" =~ grep.*\|.*grep ]]; then
        all_suggestions="${all_suggestions:+$all_suggestions,}\"Use: grep -E 'pattern1|pattern2'\""
    fi
    
    # Determine validity
    if [[ "$all_issues" =~ \"severity\":\"critical\" ]] || [[ "$all_issues" =~ \"severity\":\"error\" ]]; then
        valid="false"
    fi
    
    local elapsed=$(( $(_verify_now_ms) - start_time ))
    
    printf '{"valid":%s,"issues":[%s],"suggestions":[%s],"meta":{"elapsed_ms":%s,"timestamp":%s,"stages":%s}}' \
        "$valid" "$all_issues" "$all_suggestions" "$elapsed" "$(_verify_now_ms)" "$stage_count"
}

verify_estimate() {
    local start_time=$(_verify_now_ms)
    local cmd="$1"
    
    if [[ -z "$cmd" ]]; then
        printf '{"estimates":{"time_s":0,"memory_mb":0,"confidence":"high"},"meta":{"elapsed_ms":0,"timestamp":%s}}' "$(_verify_now_ms)"
        return 0
    fi
    
    local estimates=$(_verify_estimate_cmd "$cmd")
    local elapsed=$(( $(_verify_now_ms) - start_time ))
    
    printf '{"estimates":%s,"meta":{"elapsed_ms":%s,"timestamp":%s}}' \
        "$estimates" "$elapsed" "$(_verify_now_ms)"
}

verify_suggest_fix() {
    local start_time=$(_verify_now_ms)
    local error_output="$1"
    local fixes=""
    local confidence="low"
    
    if [[ "$error_output" =~ command[[:space:]]+not[[:space:]]+found ]]; then
        local cmd=$(echo "$error_output" | grep -oE "'[^']+'|\"[^\"]+\"|[a-zA-Z_][a-zA-Z0-9_]+$" | head -1 | tr -d "'\"" 2>/dev/null)
        
        # Check for typos
        case "$cmd" in
            sl) fixes="\"Did you mean: ls?\""; confidence="high" ;;
            gti|gir) fixes="\"Did you mean: git?\""; confidence="high" ;;
            graep|grp|gerp) fixes="\"Did you mean: grep?\""; confidence="high" ;;
            pyhton|pyton|piton) fixes="\"Did you mean: python?\""; confidence="high" ;;
            doker|dcoker) fixes="\"Did you mean: docker?\""; confidence="high" ;;
            *)
                fixes="\"Install with: apt install $cmd\",\"Install with: brew install $cmd\",\"Install with: pip install $cmd\""
                confidence="medium"
                ;;
        esac
    fi
    
    if [[ "$error_output" =~ Permission[[:space:]]+denied ]]; then
        fixes="\"Add execute permission: chmod +x <file>\",\"Run with sudo: sudo <command>\",\"Check file ownership: ls -la <file>\""
        confidence="high"
    fi
    
    if [[ "$error_output" =~ No[[:space:]]+such[[:space:]]+file[[:space:]]+or[[:space:]]+directory ]]; then
        fixes="\"Check path exists\",\"Use absolute path\",\"Create directory first: mkdir -p <dir>\""
        confidence="high"
    fi
    
    if [[ "$error_output" =~ syntax[[:space:]]+error ]]; then
        fixes="\"Check for missing quotes\",\"Check for unclosed parentheses\",\"Run: bash -n <script> to check syntax\""
        confidence="medium"
    fi
    
    local elapsed=$(( $(_verify_now_ms) - start_time ))
    
    printf '{"fixes":[%s],"confidence":"%s","meta":{"elapsed_ms":%s,"timestamp":%s}}' \
        "$fixes" "$confidence" "$elapsed" "$(_verify_now_ms)"
}

verify_and_heal() {
    local start_time=$(_verify_now_ms)
    local cmd="$1"
    
    local verify_result=$(verify_command "$cmd")
    local healed=$(_verify_heal "$cmd")
    local valid=$(echo "$verify_result" | grep -o '"valid":[a-z]*' | cut -d: -f2)
    local issues=$(echo "$verify_result" | grep -o '\[.*\]' | head -1)
    local modified="false"
    [[ "$cmd" != "$healed" ]] && modified="true"
    
    local elapsed=$(( $(_verify_now_ms) - start_time ))
    
    printf '{"valid":%s,"original":"%s","healed":"%s","issues":%s,"meta":{"elapsed_ms":%s,"timestamp":%s,"was_modified":%s}}' \
        "$valid" "$(_verify_json_escape "$cmd")" "$(_verify_json_escape "$healed")" "$issues" "$elapsed" "$(_verify_now_ms)" "$modified"
}

# Export functions
export -f verify_command 2>/dev/null || true
export -f verify_pipeline 2>/dev/null || true
export -f verify_estimate 2>/dev/null || true
export -f verify_suggest_fix 2>/dev/null || true
export -f verify_and_heal 2>/dev/null || true

_verify_log debug "Verification engine v${VERIFY_VERSION} loaded"

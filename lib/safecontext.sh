#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/safecontext.sh - Context Profiles for AI Agent Safety
# =============================================================================
# Description: Defines environment-aware safety profiles (development, staging,
#              production, testing, ci) that control risk thresholds, confirmation
#              policies, operational limits, and dry-run defaults. Enables AI
#              agents to automatically adapt behavior based on deployment context.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_SAFECONTEXT_LOADED:-}" ]] && return 0
_MAINFRAME_SAFECONTEXT_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Current active profile
_MAINFRAME_CTX_PROFILE=""

# Profile rule values (active)
_MAINFRAME_CTX_RISK_THRESHOLD=""
_MAINFRAME_CTX_CONFIRM_POLICY=""
_MAINFRAME_CTX_LIMITS=""
_MAINFRAME_CTX_DRY_RUN=""

# Override tracking
declare -gA _MAINFRAME_CTX_OVERRIDES 2>/dev/null || declare -A _MAINFRAME_CTX_OVERRIDES
_MAINFRAME_CTX_OVERRIDES=()

# Custom profiles storage: "name" -> "risk_threshold|confirm_policy|limits|dry_run"
declare -gA _MAINFRAME_CTX_CUSTOM_PROFILES 2>/dev/null || declare -A _MAINFRAME_CTX_CUSTOM_PROFILES
_MAINFRAME_CTX_CUSTOM_PROFILES=()

# Enforcement state
_MAINFRAME_CTX_ENFORCED=0

# =============================================================================
# PROFILE DEFINITIONS
# =============================================================================

# Returns profile rules as pipe-delimited: risk_threshold|confirm_policy|limits|dry_run
_ctx_profile_rules() {
    local profile="$1"

    case "$profile" in
        development)
            printf '8|never|permissive|false'
            ;;
        staging)
            printf '6|risk|moderate|false'
            ;;
        production)
            printf '3|always|strict|true'
            ;;
        testing)
            printf '10|never|none|false'
            ;;
        ci)
            printf '5|never|moderate|false'
            ;;
        *)
            # Check custom profiles
            if [[ -n "${_MAINFRAME_CTX_CUSTOM_PROFILES[$profile]:-}" ]]; then
                printf '%s' "${_MAINFRAME_CTX_CUSTOM_PROFILES[$profile]}"
            else
                return 1
            fi
            ;;
    esac
    return 0
}

# List of built-in profiles
_ctx_builtin_profiles() {
    printf 'development staging production testing ci'
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON-escape a string
_ctx_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Parse pipe-delimited rules into global state
_ctx_apply_rules() {
    local rules="$1"
    local IFS='|'
    local -a parts
    read -ra parts <<< "$rules"

    _MAINFRAME_CTX_RISK_THRESHOLD="${parts[0]}"
    _MAINFRAME_CTX_CONFIRM_POLICY="${parts[1]}"
    _MAINFRAME_CTX_LIMITS="${parts[2]}"
    _MAINFRAME_CTX_DRY_RUN="${parts[3]}"
}

# Get effective value for a key (override takes precedence)
_ctx_effective_value() {
    local key="$1"

    if [[ -n "${_MAINFRAME_CTX_OVERRIDES[$key]+isset}" ]]; then
        printf '%s' "${_MAINFRAME_CTX_OVERRIDES[$key]}"
        return 0
    fi

    case "$key" in
        risk_threshold)  printf '%s' "$_MAINFRAME_CTX_RISK_THRESHOLD" ;;
        confirm_policy)  printf '%s' "$_MAINFRAME_CTX_CONFIRM_POLICY" ;;
        limits)          printf '%s' "$_MAINFRAME_CTX_LIMITS" ;;
        dry_run)         printf '%s' "$_MAINFRAME_CTX_DRY_RUN" ;;
        *)               return 1 ;;
    esac
    return 0
}

# Validate a profile name exists
_ctx_profile_exists() {
    local profile="$1"

    case "$profile" in
        development|staging|production|testing|ci)
            return 0
            ;;
        *)
            [[ -n "${_MAINFRAME_CTX_CUSTOM_PROFILES[$profile]:-}" ]] && return 0
            return 1
            ;;
    esac
}

# Validate a rule key
_ctx_valid_key() {
    local key="$1"
    case "$key" in
        risk_threshold|confirm_policy|limits|dry_run) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# PUBLIC API
# =============================================================================

# @pre: PROFILE is a valid profile name (development, staging, production, testing, ci, or custom)
# @post: sets the active context profile and applies its rules
# @returns: 0 on success, 1 if profile unknown
#
# Set the active context profile, applying its safety parameters.
#
# Usage: mainframe_context_set production
# Usage: mainframe_context_set development
mainframe_context_set() {
    local profile="${1:-}"

    if [[ -z "$profile" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_PROFILE","msg":"No profile specified"}}\n'
        else
            printf 'Error: No profile specified\n' >&2
        fi
        return 1
    fi

    local rules
    if ! rules=$(_ctx_profile_rules "$profile"); then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_UNKNOWN","msg":"Unknown profile: %s"}}\n' \
                "$(_ctx_escape "$profile")"
            return 0
        else
            printf 'Error: Unknown profile: %s\n' "$profile" >&2
        fi
        return 1
    fi

    _MAINFRAME_CTX_PROFILE="$profile"
    _ctx_apply_rules "$rules"

    # Clear overrides on profile change
    _MAINFRAME_CTX_OVERRIDES=()
    _MAINFRAME_CTX_ENFORCED=0

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"profile":"%s","risk_threshold":%d,"confirm_policy":"%s","limits":"%s","dry_run":%s}}\n' \
            "$(_ctx_escape "$profile")" \
            "$_MAINFRAME_CTX_RISK_THRESHOLD" \
            "$_MAINFRAME_CTX_CONFIRM_POLICY" \
            "$_MAINFRAME_CTX_LIMITS" \
            "$_MAINFRAME_CTX_DRY_RUN"
    fi

    return 0
}

# @pre: none
# @post: prints current profile name to stdout
# @returns: 0 if profile is set, 1 if no profile active
#
# Get the name of the currently active context profile.
#
# Usage: current=$(mainframe_context_get)
mainframe_context_get() {
    if [[ -z "$_MAINFRAME_CTX_PROFILE" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":true,"data":""}\n'
        fi
        return 1
    fi

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":"%s"}\n' "$(_ctx_escape "$_MAINFRAME_CTX_PROFILE")"
    else
        printf '%s' "$_MAINFRAME_CTX_PROFILE"
    fi
    return 0
}

# @pre: none (reads environment variables)
# @post: detects and sets the appropriate context profile
# @returns: 0 always; sets profile based on environment
#
# Auto-detect the deployment context from environment variables and
# hostname patterns. Detection priority:
#   1. CI=true or GITHUB_ACTIONS=true -> "ci"
#   2. NODE_ENV=production or MAINFRAME_ENV=production -> "production"
#   3. NODE_ENV=test or MAINFRAME_ENV=testing -> "testing"
#   4. Hostname contains "staging" or "stg" -> "staging"
#   5. Default -> "development"
#
# Usage: mainframe_context_detect
mainframe_context_detect() {
    local detected="development"

    # Priority 1: CI environment
    if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
        detected="ci"
    # Priority 2: Production environment
    elif [[ "${NODE_ENV:-}" == "production" || "${RAILS_ENV:-}" == "production" || \
            "${MAINFRAME_ENV:-}" == "production" ]]; then
        detected="production"
    # Priority 3: Testing environment
    elif [[ "${NODE_ENV:-}" == "test" || "${RAILS_ENV:-}" == "test" || \
            "${MAINFRAME_ENV:-}" == "testing" ]]; then
        detected="testing"
    # Priority 4: Staging hostname pattern
    else
        local hostname_val=""
        hostname_val="${HOSTNAME:-}"
        if [[ -z "$hostname_val" ]]; then
            # Fallback: try to read hostname from /etc/hostname
            if [[ -r /etc/hostname ]]; then
                read -r hostname_val < /etc/hostname 2>/dev/null || true
            fi
        fi
        # Check for staging patterns in hostname
        local lower_hostname="${hostname_val,,}"
        if [[ "$lower_hostname" == *"staging"* || "$lower_hostname" == *"stg"* ]]; then
            detected="staging"
        fi
    fi

    mainframe_context_set "$detected"
    return 0
}

# @pre: none (profile may or may not be set)
# @post: prints JSON object with rules for specified or current profile
# @returns: 0 on success, 1 if no profile specified or found
#
# Display the rules for a given profile (or current if omitted) as JSON.
#
# Usage: mainframe_context_rules
# Usage: mainframe_context_rules production
mainframe_context_rules() {
    local profile="${1:-$_MAINFRAME_CTX_PROFILE}"

    if [[ -z "$profile" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_PROFILE","msg":"No profile specified or active"}}\n'
        else
            printf 'Error: No profile specified or active\n' >&2
        fi
        return 1
    fi

    local rules
    if ! rules=$(_ctx_profile_rules "$profile"); then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_UNKNOWN","msg":"Unknown profile: %s"}}\n' \
                "$(_ctx_escape "$profile")"
        else
            printf 'Error: Unknown profile: %s\n' "$profile" >&2
        fi
        return 1
    fi

    local IFS='|'
    local -a parts
    read -ra parts <<< "$rules"

    local rt="${parts[0]}"
    local cp="${parts[1]}"
    local lm="${parts[2]}"
    local dr="${parts[3]}"

    printf '{"profile":"%s","risk_threshold":%d,"confirm_policy":"%s","limits":"%s","dry_run":%s}\n' \
        "$(_ctx_escape "$profile")" "$rt" "$cp" "$lm" "$dr"
    return 0
}

# @pre: a profile must be active
# @post: applies current profile's settings to MAINFRAME_RISK_THRESHOLD and other globals
# @returns: 0 on success, 1 if no profile active
#
# Enforce the current profile by setting the corresponding MAINFRAME_*
# environment variables that other modules (risk.sh, etc.) respect.
#
# Usage: mainframe_context_enforce
mainframe_context_enforce() {
    if [[ -z "$_MAINFRAME_CTX_PROFILE" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_PROFILE","msg":"No profile active to enforce"}}\n'
        else
            printf 'Error: No profile active to enforce\n' >&2
        fi
        return 1
    fi

    local eff_threshold eff_policy eff_limits eff_dry_run

    eff_threshold=$(_ctx_effective_value "risk_threshold")
    eff_policy=$(_ctx_effective_value "confirm_policy")
    eff_limits=$(_ctx_effective_value "limits")
    eff_dry_run=$(_ctx_effective_value "dry_run")

    # Apply risk threshold to the risk module
    export MAINFRAME_RISK_THRESHOLD="$eff_threshold"

    # Apply confirm policy
    case "$eff_policy" in
        always)
            export MAINFRAME_CONFIRM_POLICY="always"
            export MAINFRAME_RISK_CONFIRM_THRESHOLD=0
            ;;
        risk)
            export MAINFRAME_CONFIRM_POLICY="risk"
            export MAINFRAME_RISK_CONFIRM_THRESHOLD="$eff_threshold"
            ;;
        never)
            export MAINFRAME_CONFIRM_POLICY="never"
            export MAINFRAME_RISK_CONFIRM_THRESHOLD=11
            ;;
    esac

    # Apply limits policy
    case "$eff_limits" in
        strict)
            export MAINFRAME_LIMITS_POLICY="strict"
            ;;
        moderate)
            export MAINFRAME_LIMITS_POLICY="moderate"
            ;;
        permissive)
            export MAINFRAME_LIMITS_POLICY="permissive"
            ;;
        none)
            export MAINFRAME_LIMITS_POLICY="none"
            ;;
    esac

    # Apply dry-run
    if [[ "$eff_dry_run" == "true" ]]; then
        export MAINFRAME_DRY_RUN=1
    else
        export MAINFRAME_DRY_RUN=0
    fi

    _MAINFRAME_CTX_ENFORCED=1

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"enforced":true,"profile":"%s","risk_threshold":%d,"confirm_policy":"%s","limits":"%s","dry_run":%s}}\n' \
            "$(_ctx_escape "$_MAINFRAME_CTX_PROFILE")" \
            "$eff_threshold" "$eff_policy" "$eff_limits" "$eff_dry_run"
    fi

    return 0
}

# @pre: KEY is one of: risk_threshold, confirm_policy, limits, dry_run
# @post: stores override for the specified key
# @returns: 0 on success, 1 on invalid key
#
# Temporarily override a single rule in the current profile.
# Overrides persist until mainframe_context_reset is called.
#
# Usage: mainframe_context_override risk_threshold 5
# Usage: mainframe_context_override dry_run true
mainframe_context_override() {
    local key="${1:-}"
    local value="${2:-}"

    if [[ -z "$key" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_KEY","msg":"No key specified"}}\n'
        else
            printf 'Error: No key specified\n' >&2
        fi
        return 1
    fi

    if ! _ctx_valid_key "$key"; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_INVALID_KEY","msg":"Invalid key: %s. Valid keys: risk_threshold, confirm_policy, limits, dry_run"}}\n' \
                "$(_ctx_escape "$key")"
        else
            printf 'Error: Invalid key: %s\n' "$key" >&2
        fi
        return 1
    fi

    _MAINFRAME_CTX_OVERRIDES["$key"]="$value"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"key":"%s","value":"%s","overrides_count":%d}}\n' \
            "$(_ctx_escape "$key")" "$(_ctx_escape "$value")" "${#_MAINFRAME_CTX_OVERRIDES[@]}"
    fi

    return 0
}

# @pre: none
# @post: clears all overrides and reverts to base profile rules; clears enforced state
# @returns: 0 always
#
# Reset all overrides and revert to the base profile defaults.
# If no profile is set, clears all state entirely.
#
# Usage: mainframe_context_reset
mainframe_context_reset() {
    _MAINFRAME_CTX_OVERRIDES=()
    _MAINFRAME_CTX_ENFORCED=0

    # Re-apply base profile rules if one is set
    if [[ -n "$_MAINFRAME_CTX_PROFILE" ]]; then
        local rules
        rules=$(_ctx_profile_rules "$_MAINFRAME_CTX_PROFILE")
        if [[ $? -eq 0 ]]; then
            _ctx_apply_rules "$rules"
        fi
    else
        _MAINFRAME_CTX_RISK_THRESHOLD=""
        _MAINFRAME_CTX_CONFIRM_POLICY=""
        _MAINFRAME_CTX_LIMITS=""
        _MAINFRAME_CTX_DRY_RUN=""
    fi

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"reset":true,"profile":"%s"}}\n' \
            "$(_ctx_escape "$_MAINFRAME_CTX_PROFILE")"
    fi

    return 0
}

# @pre: PROFILE is a valid profile name
# @post: returns 0 if current profile matches, 1 otherwise
# @returns: 0 if matching, 1 if not
#
# Check if the current context matches the specified profile.
#
# Usage: mainframe_context_is production && echo "in prod"
# Usage: if mainframe_context_is development; then echo "dev mode"; fi
mainframe_context_is() {
    local profile="${1:-}"

    if [[ -z "$profile" ]]; then
        return 1
    fi

    [[ "$_MAINFRAME_CTX_PROFILE" == "$profile" ]]
}

# @pre: PROFILE is a valid profile name
# @post: aborts (return 1) if current context does not match expected profile
# @returns: 0 if matching, 1 with error output if not
#
# Require that the current context matches the expected profile.
# Useful as a guard at the top of production-only or development-only scripts.
#
# Usage: mainframe_context_require production || exit 1
# Usage: mainframe_context_require testing
mainframe_context_require() {
    local required="${1:-}"

    if [[ -z "$required" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_PROFILE","msg":"No profile specified to require"}}\n'
        else
            printf 'Error: No profile specified to require\n' >&2
        fi
        return 1
    fi

    if [[ "$_MAINFRAME_CTX_PROFILE" != "$required" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_MISMATCH","msg":"Context mismatch: required %s, current %s","required":"%s","current":"%s"}}\n' \
                "$(_ctx_escape "$required")" "$(_ctx_escape "$_MAINFRAME_CTX_PROFILE")" \
                "$(_ctx_escape "$required")" "$(_ctx_escape "$_MAINFRAME_CTX_PROFILE")"
        else
            printf 'Error: Context mismatch: required %s, current %s\n' "$required" "$_MAINFRAME_CTX_PROFILE" >&2
        fi
        return 1
    fi

    return 0
}

# @pre: none
# @post: prints full JSON status including profile, rules, overrides, enforcement
# @returns: 0 always
#
# Display comprehensive status of the context system including active profile,
# effective rules (with overrides applied), override list, and enforcement state.
#
# Usage: mainframe_context_status
mainframe_context_status() {
    local profile="${_MAINFRAME_CTX_PROFILE:-}"
    local enforced_str="false"
    [[ "$_MAINFRAME_CTX_ENFORCED" == "1" ]] && enforced_str="true"

    if [[ -z "$profile" ]]; then
        printf '{"profile":"","rules":null,"overrides":{},"enforced":false}\n'
        return 0
    fi

    # Effective values
    local eff_threshold eff_policy eff_limits eff_dry_run
    eff_threshold=$(_ctx_effective_value "risk_threshold")
    eff_policy=$(_ctx_effective_value "confirm_policy")
    eff_limits=$(_ctx_effective_value "limits")
    eff_dry_run=$(_ctx_effective_value "dry_run")

    # Build overrides JSON
    local overrides_json="{"
    local first=true
    local key
    for key in "${!_MAINFRAME_CTX_OVERRIDES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            overrides_json+=","
        fi
        overrides_json+="\"$(_ctx_escape "$key")\":\"$(_ctx_escape "${_MAINFRAME_CTX_OVERRIDES[$key]}")\""
    done
    overrides_json+="}"

    printf '{"profile":"%s","rules":{"risk_threshold":%d,"confirm_policy":"%s","limits":"%s","dry_run":%s},"overrides":%s,"enforced":%s}\n' \
        "$(_ctx_escape "$profile")" \
        "$eff_threshold" \
        "$eff_policy" \
        "$eff_limits" \
        "$eff_dry_run" \
        "$overrides_json" \
        "$enforced_str"

    return 0
}

# @pre: none
# @post: prints list of all available profiles (built-in + custom) to stdout
# @returns: 0 always
#
# List all available context profiles (built-in and custom).
#
# Usage: mainframe_context_list
mainframe_context_list() {
    local -a profiles=()

    # Built-in profiles
    local builtin
    builtin=$(_ctx_builtin_profiles)
    local -a builtin_arr
    read -ra builtin_arr <<< "$builtin"
    profiles+=("${builtin_arr[@]}")

    # Custom profiles
    local key
    for key in "${!_MAINFRAME_CTX_CUSTOM_PROFILES[@]}"; do
        profiles+=("$key")
    done

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        local json_arr="["
        local first=true
        local p
        for p in "${profiles[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json_arr+=","
            fi
            json_arr+="\"$(_ctx_escape "$p")\""
        done
        json_arr+="]"
        printf '{"ok":true,"data":%s}\n' "$json_arr"
    else
        local p
        for p in "${profiles[@]}"; do
            printf '%s\n' "$p"
        done
    fi

    return 0
}

# @pre: NAME is non-empty; RULES_JSON contains valid rule values
# @post: registers a custom profile that can be used with mainframe_context_set
# @returns: 0 on success, 1 on invalid input
#
# Define a custom context profile with specified rules.
# RULES_JSON format: {"risk_threshold":N,"confirm_policy":"...","limits":"...","dry_run":BOOL}
# Simple key=value pairs also accepted: "risk_threshold=7 confirm_policy=risk limits=moderate dry_run=false"
#
# Usage: mainframe_context_custom "canary" '{"risk_threshold":4,"confirm_policy":"risk","limits":"strict","dry_run":true}'
# Usage: mainframe_context_custom "local" "risk_threshold=9 confirm_policy=never limits=permissive dry_run=false"
mainframe_context_custom() {
    local name="${1:-}"
    local rules_input="${2:-}"

    if [[ -z "$name" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_NAME","msg":"No profile name specified"}}\n'
        else
            printf 'Error: No profile name specified\n' >&2
        fi
        return 1
    fi

    if [[ -z "$rules_input" ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_NO_RULES","msg":"No rules specified"}}\n'
        else
            printf 'Error: No rules specified\n' >&2
        fi
        return 1
    fi

    local rt="" cp="" lm="" dr=""

    # Try to parse as JSON-like format (extract values)
    if [[ "$rules_input" == "{"* ]]; then
        # Extract risk_threshold
        if [[ "$rules_input" =~ \"risk_threshold\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            rt="${BASH_REMATCH[1]}"
        fi
        # Extract confirm_policy
        if [[ "$rules_input" =~ \"confirm_policy\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            cp="${BASH_REMATCH[1]}"
        fi
        # Extract limits
        if [[ "$rules_input" =~ \"limits\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            lm="${BASH_REMATCH[1]}"
        fi
        # Extract dry_run
        if [[ "$rules_input" =~ \"dry_run\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
            dr="${BASH_REMATCH[1]}"
        fi
    else
        # Parse as key=value pairs
        local pair
        for pair in $rules_input; do
            local k="${pair%%=*}"
            local v="${pair#*=}"
            case "$k" in
                risk_threshold) rt="$v" ;;
                confirm_policy) cp="$v" ;;
                limits) lm="$v" ;;
                dry_run) dr="$v" ;;
            esac
        done
    fi

    # Default missing values
    [[ -z "$rt" ]] && rt=5
    [[ -z "$cp" ]] && cp="risk"
    [[ -z "$lm" ]] && lm="moderate"
    [[ -z "$dr" ]] && dr="false"

    # Validate risk_threshold is numeric
    if [[ ! "$rt" =~ ^[0-9]+$ ]]; then
        if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
            printf '{"ok":false,"error":{"code":"E_CTX_INVALID_THRESHOLD","msg":"risk_threshold must be numeric"}}\n'
        else
            printf 'Error: risk_threshold must be numeric\n' >&2
        fi
        return 1
    fi

    # Validate confirm_policy
    case "$cp" in
        always|risk|never) ;;
        *)
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_CTX_INVALID_POLICY","msg":"confirm_policy must be always, risk, or never"}}\n'
            else
                printf 'Error: confirm_policy must be always, risk, or never\n' >&2
            fi
            return 1
            ;;
    esac

    # Validate limits
    case "$lm" in
        strict|moderate|permissive|none) ;;
        *)
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_CTX_INVALID_LIMITS","msg":"limits must be strict, moderate, permissive, or none"}}\n'
            else
                printf 'Error: limits must be strict, moderate, permissive, or none\n' >&2
            fi
            return 1
            ;;
    esac

    # Validate dry_run
    case "$dr" in
        true|false) ;;
        *)
            if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
                printf '{"ok":false,"error":{"code":"E_CTX_INVALID_DRY_RUN","msg":"dry_run must be true or false"}}\n'
            else
                printf 'Error: dry_run must be true or false\n' >&2
            fi
            return 1
            ;;
    esac

    # Store as pipe-delimited
    _MAINFRAME_CTX_CUSTOM_PROFILES["$name"]="${rt}|${cp}|${lm}|${dr}"

    if [[ "${MAINFRAME_OUTPUT:-}" == "json" ]]; then
        printf '{"ok":true,"data":{"name":"%s","risk_threshold":%d,"confirm_policy":"%s","limits":"%s","dry_run":%s}}\n' \
            "$(_ctx_escape "$name")" "$rt" "$cp" "$lm" "$dr"
    fi

    return 0
}

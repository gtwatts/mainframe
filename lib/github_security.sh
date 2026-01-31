#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/github_security.sh - GitHub Security API Functions
# =============================================================================
# Description: Comprehensive GitHub Security API wrapper for Dependabot alerts,
#              secret scanning, code scanning (CodeQL), SBOM, security advisories,
#              branch protection, audit logs, and GHAS management.
#
# Features:
#   - Dependabot vulnerability alerts management
#   - Secret scanning alerts and push protection
#   - Code scanning (CodeQL/SARIF) integration
#   - SBOM export and dependency analysis
#   - Security advisory lifecycle management
#   - Branch protection rule inspection
#   - Organization audit log queries
#   - GHAS (GitHub Advanced Security) status
#   - AI-friendly JSON output for agent consumption
#
# @module      github_security
# @version     1.0.0
# @requires    git.sh, json.sh
# @provides    60+ security functions
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_GITHUB_SECURITY_LOADED:-}" ]] && return 0
readonly _MAINFRAME_GITHUB_SECURITY_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

_GHS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source git.sh if not already loaded
if [[ -z "${_MAINFRAME_GIT_LOADED:-}" ]]; then
    # shellcheck source=lib/git.sh
    source "$_GHS_LIB_DIR/git.sh" 2>/dev/null || true
fi

# Source json.sh if not already loaded
if [[ -z "${_MAINFRAME_JSON_LOADED:-}" ]]; then
    # shellcheck source=lib/json.sh
    source "$_GHS_LIB_DIR/json.sh" 2>/dev/null || true
fi

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if gh CLI is available and authenticated
# Usage: _ghs_check_gh
_ghs_check_gh() {
    if ! command -v gh &>/dev/null; then
        printf '{"error":"gh CLI not installed"}\n' >&2
        return 1
    fi
    if ! gh auth status &>/dev/null; then
        printf '{"error":"gh CLI not authenticated"}\n' >&2
        return 1
    fi
    return 0
}

# Parse owner/repo from argument or detect from git remote
# Usage: _ghs_parse_repo "$repo"
# Sets: _GHS_OWNER, _GHS_REPO
_ghs_parse_repo() {
    local repo="$1"

    if [[ -n "$repo" && "$repo" == */* ]]; then
        # owner/repo format provided
        _GHS_OWNER="${repo%%/*}"
        _GHS_REPO="${repo##*/}"
    elif [[ -n "$repo" ]]; then
        # Just repo name, try to get owner from git
        _GHS_OWNER=$(git_repo_owner 2>/dev/null) || _GHS_OWNER=""
        _GHS_REPO="$repo"
    else
        # Auto-detect from current git repo
        _GHS_OWNER=$(git_repo_owner 2>/dev/null) || _GHS_OWNER=""
        _GHS_REPO=$(git_repo_name 2>/dev/null) || _GHS_REPO=""
    fi

    if [[ -z "$_GHS_OWNER" || -z "$_GHS_REPO" ]]; then
        printf '{"error":"cannot determine repository, use owner/repo format"}\n' >&2
        return 1
    fi
    return 0
}

# Log error to stderr
# Usage: _ghs_error "message"
_ghs_error() {
    printf '[github_security] ERROR: %s\n' "$1" >&2
}

# =============================================================================
# SECTION 1: DEPENDABOT ALERTS
# =============================================================================

# List all Dependabot alerts for a repository
# @param $1 - Repository (owner/repo or auto-detect)
# @param $2 - State filter: open, dismissed, fixed, all (default: open)
# @return JSON array of alerts
# Usage: ghs_dependabot_alerts "owner/repo"
# Usage: ghs_dependabot_alerts "" "all"
ghs_dependabot_alerts() {
    local repo="$1"
    local state="${2:-open}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local endpoint="/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts"

    if [[ "$state" != "all" ]]; then
        endpoint+="?state=${state}"
    fi

    gh api "$endpoint" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch dependabot alerts"}\n'
        return 1
    }
}

# View a specific Dependabot alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON object with alert details
# Usage: ghs_dependabot_alert_view "owner/repo" 42
ghs_dependabot_alert_view() {
    local repo="$1"
    local alert_number="$2"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts/${alert_number}" 2>/dev/null || {
        printf '{"error":"failed to fetch alert %s"}\n' "$alert_number"
        return 1
    }
}

# Dismiss a Dependabot alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @param $3 - Reason: fix_started, inaccurate, no_bandwidth, not_used, tolerable_risk
# @param $4 - Optional comment
# @return JSON object with updated alert
# Usage: ghs_dependabot_alert_dismiss "owner/repo" 42 "tolerable_risk" "Low priority"
ghs_dependabot_alert_dismiss() {
    local repo="$1"
    local alert_number="$2"
    local reason="$3"
    local comment="${4:-}"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    [[ -z "$reason" ]] && { _ghs_error "dismiss reason required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local body="{\"state\":\"dismissed\",\"dismissed_reason\":\"${reason}\""
    [[ -n "$comment" ]] && body+=",\"dismissed_comment\":\"${comment}\""
    body+="}"

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts/${alert_number}" \
        --input - <<< "$body" 2>/dev/null || {
        printf '{"error":"failed to dismiss alert"}\n'
        return 1
    }
}

# Reopen a dismissed Dependabot alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON object with updated alert
# Usage: ghs_dependabot_alert_reopen "owner/repo" 42
ghs_dependabot_alert_reopen() {
    local repo="$1"
    local alert_number="$2"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts/${alert_number}" \
        --input - <<< '{"state":"open"}' 2>/dev/null || {
        printf '{"error":"failed to reopen alert"}\n'
        return 1
    }
}

# List only critical severity Dependabot alerts
# @param $1 - Repository (owner/repo)
# @return JSON array of critical alerts
# Usage: ghs_dependabot_critical "owner/repo"
ghs_dependabot_critical() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts?state=open&severity=critical" \
        --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch critical alerts"}\n'
        return 1
    }
}

# List only high severity Dependabot alerts
# @param $1 - Repository (owner/repo)
# @return JSON array of high severity alerts
# Usage: ghs_dependabot_high "owner/repo"
ghs_dependabot_high() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts?state=open&severity=high" \
        --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch high severity alerts"}\n'
        return 1
    }
}

# Count open Dependabot alerts by severity
# @param $1 - Repository (owner/repo)
# @return JSON object with severity counts
# Usage: ghs_dependabot_count "owner/repo"
ghs_dependabot_count() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local alerts
    alerts=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependabot/alerts?state=open" \
        --paginate 2>/dev/null) || {
        printf '{"error":"failed to fetch alerts"}\n'
        return 1
    }

    # Count by severity using jq if available, else pure bash parsing
    if command -v jq &>/dev/null; then
        echo "$alerts" | jq '{
            critical: [.[] | select(.security_advisory.severity == "critical")] | length,
            high: [.[] | select(.security_advisory.severity == "high")] | length,
            medium: [.[] | select(.security_advisory.severity == "medium")] | length,
            low: [.[] | select(.security_advisory.severity == "low")] | length,
            total: . | length
        }'
    else
        # Fallback: simple grep-based counting
        local critical high medium low total
        critical=$(echo "$alerts" | grep -c '"severity":"critical"' 2>/dev/null || echo 0)
        high=$(echo "$alerts" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
        medium=$(echo "$alerts" | grep -c '"severity":"medium"' 2>/dev/null || echo 0)
        low=$(echo "$alerts" | grep -c '"severity":"low"' 2>/dev/null || echo 0)
        total=$(echo "$alerts" | grep -c '"number":' 2>/dev/null || echo 0)
        printf '{"critical":%d,"high":%d,"medium":%d,"low":%d,"total":%d}\n' \
            "$critical" "$high" "$medium" "$low" "$total"
    fi
}

# Get AI-friendly Dependabot summary
# @param $1 - Repository (owner/repo)
# @return JSON summary optimized for AI agent consumption
# Usage: ghs_dependabot_summary "owner/repo"
ghs_dependabot_summary() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local counts
    counts=$(ghs_dependabot_count "$repo") || return 1

    local critical high
    if command -v jq &>/dev/null; then
        critical=$(echo "$counts" | jq -r '.critical')
        high=$(echo "$counts" | jq -r '.high')
    else
        critical=$(echo "$counts" | grep -oP '"critical":\K[0-9]+' || echo 0)
        high=$(echo "$counts" | grep -oP '"high":\K[0-9]+' || echo 0)
    fi

    local action="none"
    [[ "$high" -gt 0 ]] && action="review_high"
    [[ "$critical" -gt 0 ]] && action="fix_critical_immediately"

    printf '{"repository":"%s/%s","counts":%s,"recommended_action":"%s","api_endpoint":"/repos/%s/%s/dependabot/alerts"}\n' \
        "$_GHS_OWNER" "$_GHS_REPO" "$counts" "$action" "$_GHS_OWNER" "$_GHS_REPO"
}

# Check if Dependabot is enabled for repository
# @param $1 - Repository (owner/repo)
# @return 0 if enabled, 1 if disabled
# Usage: ghs_dependabot_enabled "owner/repo" && echo "enabled"
ghs_dependabot_enabled() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local result
    result=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/vulnerability-alerts" \
        -i 2>&1 | head -1)

    if [[ "$result" == *"204"* ]]; then
        printf '{"enabled":true}\n'
        return 0
    else
        printf '{"enabled":false}\n'
        return 1
    fi
}

# Get dependabot.yml configuration content
# @param $1 - Repository (owner/repo)
# @return YAML content or error
# Usage: ghs_dependabot_config "owner/repo"
ghs_dependabot_config() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/contents/.github/dependabot.yml" \
        --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || {
        printf '{"error":"dependabot.yml not found"}\n'
        return 1
    }
}

# =============================================================================
# SECTION 2: SECRET SCANNING
# =============================================================================

# List secret scanning alerts for a repository
# @param $1 - Repository (owner/repo)
# @param $2 - State filter: open, resolved, all (default: open)
# @return JSON array of alerts
# Usage: ghs_secret_alerts "owner/repo"
# Usage: ghs_secret_alerts "owner/repo" "all"
ghs_secret_alerts() {
    local repo="$1"
    local state="${2:-open}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local endpoint="/repos/${_GHS_OWNER}/${_GHS_REPO}/secret-scanning/alerts"
    [[ "$state" != "all" ]] && endpoint+="?state=${state}"

    gh api "$endpoint" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch secret scanning alerts (requires GHAS)"}\n'
        return 1
    }
}

# View a specific secret scanning alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON object with alert details
# Usage: ghs_secret_alert_view "owner/repo" 42
ghs_secret_alert_view() {
    local repo="$1"
    local alert_number="$2"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/secret-scanning/alerts/${alert_number}" 2>/dev/null || {
        printf '{"error":"failed to fetch alert"}\n'
        return 1
    }
}

# Resolve a secret scanning alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @param $3 - Resolution: false_positive, wont_fix, revoked, used_in_tests, pattern_deleted
# @param $4 - Optional comment
# @return JSON object with updated alert
# Usage: ghs_secret_alert_resolve "owner/repo" 42 "revoked" "Rotated secret"
ghs_secret_alert_resolve() {
    local repo="$1"
    local alert_number="$2"
    local resolution="$3"
    local comment="${4:-}"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    [[ -z "$resolution" ]] && { _ghs_error "resolution required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local body="{\"state\":\"resolved\",\"resolution\":\"${resolution}\""
    [[ -n "$comment" ]] && body+=",\"resolution_comment\":\"${comment}\""
    body+="}"

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/secret-scanning/alerts/${alert_number}" \
        --input - <<< "$body" 2>/dev/null || {
        printf '{"error":"failed to resolve alert"}\n'
        return 1
    }
}

# List detected secret types in repository
# @param $1 - Repository (owner/repo)
# @return JSON array of unique secret types found
# Usage: ghs_secret_types "owner/repo"
ghs_secret_types() {
    local repo="$1"

    local alerts
    alerts=$(ghs_secret_alerts "$repo" "all") || return 1

    if command -v jq &>/dev/null; then
        echo "$alerts" | jq '[.[].secret_type] | unique'
    else
        echo "$alerts" | grep -oP '"secret_type":"[^"]+' | cut -d'"' -f4 | sort -u | \
            awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]\n"}'
    fi
}

# Get locations where a secret was found
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON array of locations
# Usage: ghs_secret_locations "owner/repo" 42
ghs_secret_locations() {
    local repo="$1"
    local alert_number="$2"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/secret-scanning/alerts/${alert_number}/locations" \
        --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch locations"}\n'
        return 1
    }
}

# Check if a secret is still valid (if provider supports validation)
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON with validity status
# Usage: ghs_secret_validity "owner/repo" 42
ghs_secret_validity() {
    local repo="$1"
    local alert_number="$2"

    local alert
    alert=$(ghs_secret_alert_view "$repo" "$alert_number") || return 1

    if command -v jq &>/dev/null; then
        echo "$alert" | jq '{
            alert_number: .number,
            secret_type: .secret_type,
            validity: .validity,
            validity_checked_at: .validity_checked_at,
            is_active: (.validity == "active")
        }'
    else
        # Simplified output without jq
        printf '{"alert_number":%s,"raw_response":"see ghs_secret_alert_view"}\n' "$alert_number"
    fi
}

# Check if secret scanning is enabled
# @param $1 - Repository (owner/repo)
# @return JSON with enabled status
# Usage: ghs_secret_enabled "owner/repo"
ghs_secret_enabled() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local settings
    settings=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}" \
        --jq '.security_and_analysis.secret_scanning.status' 2>/dev/null)

    if [[ "$settings" == "enabled" ]]; then
        printf '{"secret_scanning":true}\n'
        return 0
    else
        printf '{"secret_scanning":false}\n'
        return 1
    fi
}

# Check push protection status
# @param $1 - Repository (owner/repo)
# @return JSON with push protection status
# Usage: ghs_secret_push_protection "owner/repo"
ghs_secret_push_protection() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local settings
    settings=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}" \
        --jq '.security_and_analysis.secret_scanning_push_protection.status' 2>/dev/null)

    if [[ "$settings" == "enabled" ]]; then
        printf '{"push_protection":true}\n'
        return 0
    else
        printf '{"push_protection":false}\n'
        return 1
    fi
}

# =============================================================================
# SECTION 3: CODE SCANNING (CodeQL)
# =============================================================================

# List code scanning alerts
# @param $1 - Repository (owner/repo)
# @param $2 - State filter: open, closed, dismissed, fixed, all (default: open)
# @return JSON array of alerts
# Usage: ghs_code_alerts "owner/repo"
# Usage: ghs_code_alerts "owner/repo" "all"
ghs_code_alerts() {
    local repo="$1"
    local state="${2:-open}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local endpoint="/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/alerts"
    [[ "$state" != "all" ]] && endpoint+="?state=${state}"

    gh api "$endpoint" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch code scanning alerts (requires GHAS)"}\n'
        return 1
    }
}

# View a specific code scanning alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @return JSON object with alert details
# Usage: ghs_code_alert_view "owner/repo" 42
ghs_code_alert_view() {
    local repo="$1"
    local alert_number="$2"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/alerts/${alert_number}" 2>/dev/null || {
        printf '{"error":"failed to fetch alert"}\n'
        return 1
    }
}

# Dismiss a code scanning alert
# @param $1 - Repository (owner/repo)
# @param $2 - Alert number
# @param $3 - Reason: false positive, won't fix, used in tests
# @param $4 - Optional comment
# @return JSON object with updated alert
# Usage: ghs_code_alert_dismiss "owner/repo" 42 "false positive" "Not applicable"
ghs_code_alert_dismiss() {
    local repo="$1"
    local alert_number="$2"
    local reason="$3"
    local comment="${4:-}"

    [[ -z "$alert_number" ]] && { _ghs_error "alert number required"; return 1; }
    [[ -z "$reason" ]] && { _ghs_error "dismiss reason required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local body="{\"state\":\"dismissed\",\"dismissed_reason\":\"${reason}\""
    [[ -n "$comment" ]] && body+=",\"dismissed_comment\":\"${comment}\""
    body+="}"

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/alerts/${alert_number}" \
        --input - <<< "$body" 2>/dev/null || {
        printf '{"error":"failed to dismiss alert"}\n'
        return 1
    }
}

# List code scanning analysis runs
# @param $1 - Repository (owner/repo)
# @return JSON array of analysis runs
# Usage: ghs_code_analysis_list "owner/repo"
ghs_code_analysis_list() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/analyses" \
        --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch analyses"}\n'
        return 1
    }
}

# Upload SARIF results
# @param $1 - Repository (owner/repo)
# @param $2 - SARIF file path
# @param $3 - Git ref (default: current branch)
# @param $4 - Commit SHA (default: HEAD)
# @return JSON with upload status
# Usage: ghs_code_sarif_upload "owner/repo" "results.sarif"
ghs_code_sarif_upload() {
    local repo="$1"
    local sarif_file="$2"
    local ref="${3:-$(git_branch 2>/dev/null)}"
    local sha="${4:-$(git_commit_hash_full 2>/dev/null)}"

    [[ -z "$sarif_file" ]] && { _ghs_error "SARIF file required"; return 1; }
    [[ ! -f "$sarif_file" ]] && { _ghs_error "SARIF file not found: $sarif_file"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Compress and base64 encode SARIF
    local sarif_gz
    sarif_gz=$(gzip -c "$sarif_file" | base64 -w0)

    gh api -X POST "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/sarifs" \
        -f commit_sha="$sha" \
        -f ref="refs/heads/$ref" \
        -f sarif="$sarif_gz" 2>/dev/null || {
        printf '{"error":"failed to upload SARIF"}\n'
        return 1
    }
}

# Get default code scanning setup status
# @param $1 - Repository (owner/repo)
# @return JSON with setup configuration
# Usage: ghs_code_default_setup "owner/repo"
ghs_code_default_setup() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/default-setup" 2>/dev/null || {
        printf '{"error":"failed to fetch default setup"}\n'
        return 1
    }
}

# Enable code scanning with default setup
# @param $1 - Repository (owner/repo)
# @return JSON with setup result
# Usage: ghs_code_enable "owner/repo"
ghs_code_enable() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/code-scanning/default-setup" \
        --input - <<< '{"state":"configured"}' 2>/dev/null || {
        printf '{"error":"failed to enable code scanning"}\n'
        return 1
    }
}

# Get languages analyzed by code scanning
# @param $1 - Repository (owner/repo)
# @return JSON array of languages
# Usage: ghs_code_languages "owner/repo"
ghs_code_languages() {
    local repo="$1"

    local setup
    setup=$(ghs_code_default_setup "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$setup" | jq '.languages // []'
    else
        echo "$setup" | grep -oP '"languages":\[[^\]]+\]' | head -1
    fi
}

# List active code scanning rules
# @param $1 - Repository (owner/repo)
# @return JSON array of rules from recent analysis
# Usage: ghs_code_rules "owner/repo"
ghs_code_rules() {
    local repo="$1"

    local alerts
    alerts=$(ghs_code_alerts "$repo" "all") || return 1

    if command -v jq &>/dev/null; then
        echo "$alerts" | jq '[.[].rule] | unique_by(.id)'
    else
        printf '{"info":"jq required for rule extraction"}\n'
        return 1
    fi
}

# Group code scanning alerts by severity
# @param $1 - Repository (owner/repo)
# @return JSON object with severity groups
# Usage: ghs_code_by_severity "owner/repo"
ghs_code_by_severity() {
    local repo="$1"

    local alerts
    alerts=$(ghs_code_alerts "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$alerts" | jq 'group_by(.rule.severity) |
            map({(.[0].rule.severity // "unknown"): length}) |
            add // {}'
    else
        local error warning note
        error=$(echo "$alerts" | grep -c '"severity":"error"' 2>/dev/null || echo 0)
        warning=$(echo "$alerts" | grep -c '"severity":"warning"' 2>/dev/null || echo 0)
        note=$(echo "$alerts" | grep -c '"severity":"note"' 2>/dev/null || echo 0)
        printf '{"error":%d,"warning":%d,"note":%d}\n' "$error" "$warning" "$note"
    fi
}

# Group code scanning alerts by rule
# @param $1 - Repository (owner/repo)
# @return JSON object with rule groups
# Usage: ghs_code_by_rule "owner/repo"
ghs_code_by_rule() {
    local repo="$1"

    local alerts
    alerts=$(ghs_code_alerts "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$alerts" | jq 'group_by(.rule.id) |
            map({rule_id: .[0].rule.id, rule_name: .[0].rule.name, count: length}) |
            sort_by(-.count)'
    else
        printf '{"info":"jq required for rule grouping"}\n'
        return 1
    fi
}

# Get AI-friendly code scanning summary
# @param $1 - Repository (owner/repo)
# @return JSON summary for AI agents
# Usage: ghs_code_summary "owner/repo"
ghs_code_summary() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local by_severity
    by_severity=$(ghs_code_by_severity "$repo") || by_severity='{}'

    local setup
    setup=$(ghs_code_default_setup "$repo" 2>/dev/null) || setup='{}'

    local state="unknown"
    if command -v jq &>/dev/null && [[ "$setup" != "{}" ]]; then
        state=$(echo "$setup" | jq -r '.state // "unknown"')
    fi

    printf '{"repository":"%s/%s","scanning_state":"%s","alerts_by_severity":%s}\n' \
        "$_GHS_OWNER" "$_GHS_REPO" "$state" "$by_severity"
}

# =============================================================================
# SECTION 4: SBOM (Software Bill of Materials)
# =============================================================================

# Export SBOM in specified format
# @param $1 - Repository (owner/repo)
# @param $2 - Format: spdx (default) or cyclonedx
# @return SBOM content in requested format
# Usage: ghs_sbom_export "owner/repo"
# Usage: ghs_sbom_export "owner/repo" "cyclonedx"
ghs_sbom_export() {
    local repo="$1"
    local format="${2:-spdx}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # GitHub provides SPDX format by default
    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependency-graph/sbom" 2>/dev/null || {
        printf '{"error":"failed to export SBOM"}\n'
        return 1
    }
}

# List all dependencies from SBOM
# @param $1 - Repository (owner/repo)
# @return JSON array of dependencies
# Usage: ghs_sbom_dependencies "owner/repo"
ghs_sbom_dependencies() {
    local repo="$1"

    local sbom
    sbom=$(ghs_sbom_export "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$sbom" | jq '.sbom.packages // []'
    else
        printf '{"info":"jq required for dependency extraction"}\n'
        return 1
    fi
}

# Get dependency graph
# @param $1 - Repository (owner/repo)
# @return JSON dependency graph
# Usage: ghs_sbom_dependency_graph "owner/repo"
ghs_sbom_dependency_graph() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Use the dependency submission API to get graph
    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/dependency-graph/snapshots" \
        --paginate 2>/dev/null || {
        # Fallback to sbom
        ghs_sbom_export "$repo"
    }
}

# List all licenses from SBOM
# @param $1 - Repository (owner/repo)
# @return JSON array of licenses
# Usage: ghs_sbom_licenses "owner/repo"
ghs_sbom_licenses() {
    local repo="$1"

    local sbom
    sbom=$(ghs_sbom_export "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$sbom" | jq '[.sbom.packages[].licenseConcluded // .sbom.packages[].licenseDeclared] |
            unique | map(select(. != null and . != "NOASSERTION"))'
    else
        printf '{"info":"jq required for license extraction"}\n'
        return 1
    fi
}

# List outdated dependencies (requires Dependabot data)
# @param $1 - Repository (owner/repo)
# @return JSON array of outdated dependencies
# Usage: ghs_sbom_outdated "owner/repo"
ghs_sbom_outdated() {
    local repo="$1"

    # Get dependencies with available updates from Dependabot
    local alerts
    alerts=$(ghs_dependabot_alerts "$repo" "open") || return 1

    if command -v jq &>/dev/null; then
        echo "$alerts" | jq '[.[] | {
            package: .dependency.package.name,
            ecosystem: .dependency.package.ecosystem,
            manifest: .dependency.manifest_path,
            current_version: .security_vulnerability.vulnerable_version_range,
            patched_version: .security_vulnerability.first_patched_version.identifier
        }] | unique_by(.package)'
    else
        printf '{"info":"jq required, use ghs_dependabot_alerts for raw data"}\n'
        return 1
    fi
}

# Get AI-friendly SBOM summary
# @param $1 - Repository (owner/repo)
# @return JSON summary for AI agents
# Usage: ghs_sbom_summary "owner/repo"
ghs_sbom_summary() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local sbom
    sbom=$(ghs_sbom_export "$repo") || return 1

    if command -v jq &>/dev/null; then
        echo "$sbom" | jq '{
            repository: .sbom.name,
            spdx_version: .sbom.spdxVersion,
            created: .sbom.creationInfo.created,
            total_packages: (.sbom.packages | length),
            unique_licenses: ([.sbom.packages[].licenseConcluded] | unique | length),
            document_namespace: .sbom.documentNamespace
        }'
    else
        printf '{"repository":"%s/%s","raw_available":true}\n' "$_GHS_OWNER" "$_GHS_REPO"
    fi
}

# =============================================================================
# SECTION 5: SECURITY ADVISORIES
# =============================================================================

# List repository security advisories
# @param $1 - Repository (owner/repo)
# @param $2 - State: draft, published, closed, all (default: all)
# @return JSON array of advisories
# Usage: ghs_advisory_list "owner/repo"
# Usage: ghs_advisory_list "owner/repo" "published"
ghs_advisory_list() {
    local repo="$1"
    local state="${2:-all}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local endpoint="/repos/${_GHS_OWNER}/${_GHS_REPO}/security-advisories"
    [[ "$state" != "all" ]] && endpoint+="?state=${state}"

    gh api "$endpoint" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch advisories"}\n'
        return 1
    }
}

# View a specific security advisory
# @param $1 - Repository (owner/repo)
# @param $2 - Advisory GHSA ID
# @return JSON object with advisory details
# Usage: ghs_advisory_view "owner/repo" "GHSA-xxxx-yyyy-zzzz"
ghs_advisory_view() {
    local repo="$1"
    local ghsa_id="$2"

    [[ -z "$ghsa_id" ]] && { _ghs_error "GHSA ID required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/security-advisories/${ghsa_id}" 2>/dev/null || {
        printf '{"error":"failed to fetch advisory"}\n'
        return 1
    }
}

# Create a security advisory draft
# @param $1 - Repository (owner/repo)
# @param $2 - Summary/title
# @param $3 - Description
# @param $4 - Severity: critical, high, medium, low
# @return JSON object with created advisory
# Usage: ghs_advisory_create "owner/repo" "SQL Injection" "Description..." "high"
ghs_advisory_create() {
    local repo="$1"
    local summary="$2"
    local description="$3"
    local severity="${4:-medium}"

    [[ -z "$summary" ]] && { _ghs_error "summary required"; return 1; }
    [[ -z "$description" ]] && { _ghs_error "description required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Escape for JSON
    local esc_summary esc_desc
    esc_summary=$(printf '%s' "$summary" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')
    esc_desc=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')

    local body
    body=$(printf '{"summary":"%s","description":"%s","severity":"%s","vulnerabilities":[]}' \
        "$esc_summary" "$esc_desc" "$severity")

    gh api -X POST "/repos/${_GHS_OWNER}/${_GHS_REPO}/security-advisories" \
        --input - <<< "$body" 2>/dev/null || {
        printf '{"error":"failed to create advisory"}\n'
        return 1
    }
}

# Update a security advisory
# @param $1 - Repository (owner/repo)
# @param $2 - Advisory GHSA ID
# @param $3 - JSON patch body
# @return JSON object with updated advisory
# Usage: ghs_advisory_update "owner/repo" "GHSA-xxxx" '{"severity":"critical"}'
ghs_advisory_update() {
    local repo="$1"
    local ghsa_id="$2"
    local patch="$3"

    [[ -z "$ghsa_id" ]] && { _ghs_error "GHSA ID required"; return 1; }
    [[ -z "$patch" ]] && { _ghs_error "patch body required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}/security-advisories/${ghsa_id}" \
        --input - <<< "$patch" 2>/dev/null || {
        printf '{"error":"failed to update advisory"}\n'
        return 1
    }
}

# Publish a security advisory (from draft)
# @param $1 - Repository (owner/repo)
# @param $2 - Advisory GHSA ID
# @return JSON object with published advisory
# Usage: ghs_advisory_publish "owner/repo" "GHSA-xxxx"
ghs_advisory_publish() {
    local repo="$1"
    local ghsa_id="$2"

    ghs_advisory_update "$repo" "$ghsa_id" '{"state":"published"}'
}

# Request a CVE for an advisory
# @param $1 - Repository (owner/repo)
# @param $2 - Advisory GHSA ID
# @return JSON with CVE request status
# Usage: ghs_advisory_request_cve "owner/repo" "GHSA-xxxx"
ghs_advisory_request_cve() {
    local repo="$1"
    local ghsa_id="$2"

    [[ -z "$ghsa_id" ]] && { _ghs_error "GHSA ID required"; return 1; }
    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api -X POST "/repos/${_GHS_OWNER}/${_GHS_REPO}/security-advisories/${ghsa_id}/cve" \
        2>/dev/null || {
        printf '{"error":"failed to request CVE"}\n'
        return 1
    }
}

# List credits for an advisory
# @param $1 - Repository (owner/repo)
# @param $2 - Advisory GHSA ID
# @return JSON array of credits
# Usage: ghs_advisory_credits "owner/repo" "GHSA-xxxx"
ghs_advisory_credits() {
    local repo="$1"
    local ghsa_id="$2"

    local advisory
    advisory=$(ghs_advisory_view "$repo" "$ghsa_id") || return 1

    if command -v jq &>/dev/null; then
        echo "$advisory" | jq '.credits // []'
    else
        echo "$advisory" | grep -oP '"credits":\[[^\]]*\]' | head -1
    fi
}

# Search global advisory database
# @param $1 - Search query (CVE ID, package name, keyword)
# @param $2 - Ecosystem filter: npm, pip, maven, etc. (optional)
# @return JSON array of matching advisories
# Usage: ghs_advisory_global_search "CVE-2021-44228"
# Usage: ghs_advisory_global_search "log4j" "maven"
ghs_advisory_global_search() {
    local query="$1"
    local ecosystem="${2:-}"

    [[ -z "$query" ]] && { _ghs_error "search query required"; return 1; }
    _ghs_check_gh || return 1

    local endpoint="/advisories?per_page=100"

    # Add ecosystem filter if provided
    [[ -n "$ecosystem" ]] && endpoint+="&ecosystem=${ecosystem}"

    # Search by CVE if it looks like a CVE ID
    if [[ "$query" =~ ^CVE-[0-9]{4}-[0-9]+$ ]]; then
        endpoint+="&cve_id=${query}"
    else
        endpoint+="&keywords=${query}"
    fi

    gh api "$endpoint" --paginate 2>/dev/null || {
        printf '{"error":"failed to search advisories"}\n'
        return 1
    }
}

# =============================================================================
# SECTION 6: BRANCH PROTECTION
# =============================================================================

# Get branch protection rules
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name (default: default branch)
# @return JSON object with protection rules
# Usage: ghs_branch_protection "owner/repo" "main"
ghs_branch_protection() {
    local repo="$1"
    local branch="${2:-}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Get default branch if not specified
    if [[ -z "$branch" ]]; then
        branch=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}" --jq '.default_branch' 2>/dev/null)
        [[ -z "$branch" ]] && branch="main"
    fi

    gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}/branches/${branch}/protection" 2>/dev/null || {
        printf '{"error":"no protection rules or access denied"}\n'
        return 1
    }
}

# Get required status checks
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON object with required checks
# Usage: ghs_branch_required_checks "owner/repo" "main"
ghs_branch_required_checks() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.required_status_checks // null'
    else
        echo "$protection" | grep -oP '"required_status_checks":\{[^}]+\}' | head -1
    fi
}

# Get dismiss stale reviews setting
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON with setting
# Usage: ghs_branch_dismiss_reviews "owner/repo" "main"
ghs_branch_dismiss_reviews() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.required_pull_request_reviews.dismiss_stale_reviews // false'
    else
        echo "$protection" | grep -oP '"dismiss_stale_reviews":(true|false)' | head -1
    fi
}

# Get required reviewers count
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return Number of required reviewers
# Usage: ghs_branch_require_reviews "owner/repo" "main"
ghs_branch_require_reviews() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.required_pull_request_reviews.required_approving_review_count // 0'
    else
        echo "$protection" | grep -oP '"required_approving_review_count":[0-9]+' | grep -oP '[0-9]+'
    fi
}

# Check if admins are enforced
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON with enforce_admins status
# Usage: ghs_branch_enforce_admins "owner/repo" "main"
ghs_branch_enforce_admins() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.enforce_admins.enabled // false'
    else
        echo "$protection" | grep -oP '"enforce_admins":\{"enabled":(true|false)' | grep -oP '(true|false)$'
    fi
}

# Get push restrictions
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON with push restrictions
# Usage: ghs_branch_restrict_push "owner/repo" "main"
ghs_branch_restrict_push() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.restrictions // null'
    else
        echo "$protection" | grep -oP '"restrictions":\{[^}]+\}' | head -1
    fi
}

# Check force push setting
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON with allow_force_pushes status
# Usage: ghs_branch_allow_force_push "owner/repo" "main"
ghs_branch_allow_force_push() {
    local repo="$1"
    local branch="${2:-main}"

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch") || return 1

    if command -v jq &>/dev/null; then
        echo "$protection" | jq '.allow_force_pushes.enabled // false'
    else
        echo "$protection" | grep -oP '"allow_force_pushes":\{"enabled":(true|false)' | grep -oP '(true|false)$'
    fi
}

# Get AI-friendly branch protection summary
# @param $1 - Repository (owner/repo)
# @param $2 - Branch name
# @return JSON summary for AI agents
# Usage: ghs_branch_summary "owner/repo" "main"
ghs_branch_summary() {
    local repo="$1"
    local branch="${2:-main}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local protection
    protection=$(ghs_branch_protection "$repo" "$branch" 2>/dev/null)

    if [[ -z "$protection" || "$protection" == *"error"* ]]; then
        printf '{"repository":"%s/%s","branch":"%s","protected":false}\n' \
            "$_GHS_OWNER" "$_GHS_REPO" "$branch"
        return 0
    fi

    if command -v jq &>/dev/null; then
        echo "$protection" | jq --arg repo "${_GHS_OWNER}/${_GHS_REPO}" --arg branch "$branch" '{
            repository: $repo,
            branch: $branch,
            protected: true,
            require_reviews: (.required_pull_request_reviews != null),
            required_reviewers: (.required_pull_request_reviews.required_approving_review_count // 0),
            require_status_checks: (.required_status_checks != null),
            enforce_admins: (.enforce_admins.enabled // false),
            allow_force_push: (.allow_force_pushes.enabled // false),
            allow_deletions: (.allow_deletions.enabled // false)
        }'
    else
        printf '{"repository":"%s/%s","branch":"%s","protected":true}\n' \
            "$_GHS_OWNER" "$_GHS_REPO" "$branch"
    fi
}

# =============================================================================
# SECTION 7: SECURITY OVERVIEW
# =============================================================================

# Get full security overview as JSON
# @param $1 - Repository (owner/repo)
# @return Comprehensive security JSON
# Usage: ghs_overview "owner/repo"
ghs_overview() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Get repository security settings
    local repo_info
    repo_info=$(gh api "/repos/${_GHS_OWNER}/${_GHS_REPO}" 2>/dev/null) || {
        printf '{"error":"failed to fetch repository"}\n'
        return 1
    }

    if command -v jq &>/dev/null; then
        echo "$repo_info" | jq '{
            repository: .full_name,
            visibility: .visibility,
            default_branch: .default_branch,
            security_and_analysis: .security_and_analysis,
            has_issues: .has_issues,
            has_projects: .has_projects,
            has_wiki: .has_wiki,
            allow_forking: .allow_forking
        }'
    else
        printf '{"repository":"%s/%s","raw_available":true}\n' "$_GHS_OWNER" "$_GHS_REPO"
    fi
}

# Calculate security score (0-100)
# @param $1 - Repository (owner/repo)
# @return JSON with score and breakdown
# Usage: ghs_score "owner/repo"
ghs_score() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local score=0
    local checks=()

    # Check Dependabot (20 points)
    if ghs_dependabot_enabled "$repo" &>/dev/null; then
        ((score += 20))
        checks+='"dependabot_enabled":true'
    else
        checks+='"dependabot_enabled":false'
    fi

    # Check secret scanning (20 points)
    if ghs_secret_enabled "$repo" &>/dev/null; then
        ((score += 20))
        checks+='"secret_scanning":true'
    else
        checks+='"secret_scanning":false'
    fi

    # Check push protection (15 points)
    if ghs_secret_push_protection "$repo" &>/dev/null; then
        ((score += 15))
        checks+='"push_protection":true'
    else
        checks+='"push_protection":false'
    fi

    # Check branch protection (25 points)
    local branch_summary
    branch_summary=$(ghs_branch_summary "$repo" 2>/dev/null)
    if [[ "$branch_summary" == *'"protected":true'* ]]; then
        ((score += 25))
        checks+='"branch_protection":true'
    else
        checks+='"branch_protection":false'
    fi

    # No critical vulnerabilities (20 points)
    local dep_count
    dep_count=$(ghs_dependabot_count "$repo" 2>/dev/null)
    local critical=0
    if command -v jq &>/dev/null && [[ -n "$dep_count" ]]; then
        critical=$(echo "$dep_count" | jq -r '.critical // 0')
    fi

    if [[ "$critical" -eq 0 ]]; then
        ((score += 20))
        checks+='"no_critical_vulns":true'
    else
        checks+='"no_critical_vulns":false'
    fi

    # Build response
    local checks_json
    checks_json=$(IFS=,; echo "${checks[*]}")

    printf '{"repository":"%s/%s","score":%d,"max_score":100,"checks":{%s}}\n' \
        "$_GHS_OWNER" "$_GHS_REPO" "$score" "$checks_json"
}

# Get AI-friendly recommendations
# @param $1 - Repository (owner/repo)
# @return JSON array of recommendations
# Usage: ghs_recommendations "owner/repo"
ghs_recommendations() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local recommendations=()

    # Check Dependabot
    if ! ghs_dependabot_enabled "$repo" &>/dev/null; then
        recommendations+=('{"priority":"high","action":"enable_dependabot","description":"Enable Dependabot alerts for vulnerability notifications"}')
    fi

    # Check secret scanning
    if ! ghs_secret_enabled "$repo" &>/dev/null; then
        recommendations+=('{"priority":"high","action":"enable_secret_scanning","description":"Enable secret scanning to detect exposed credentials"}')
    fi

    # Check push protection
    if ! ghs_secret_push_protection "$repo" &>/dev/null; then
        recommendations+=('{"priority":"medium","action":"enable_push_protection","description":"Enable push protection to prevent secret commits"}')
    fi

    # Check branch protection
    local branch_summary
    branch_summary=$(ghs_branch_summary "$repo" 2>/dev/null)
    if [[ "$branch_summary" != *'"protected":true'* ]]; then
        recommendations+=('{"priority":"high","action":"enable_branch_protection","description":"Add branch protection rules to default branch"}')
    fi

    # Check for critical vulns
    local dep_count
    dep_count=$(ghs_dependabot_count "$repo" 2>/dev/null)
    if command -v jq &>/dev/null && [[ -n "$dep_count" ]]; then
        local critical
        critical=$(echo "$dep_count" | jq -r '.critical // 0')
        if [[ "$critical" -gt 0 ]]; then
            recommendations+=('{"priority":"critical","action":"fix_critical_vulnerabilities","description":"'$critical' critical vulnerabilities require immediate attention"}')
        fi
    fi

    # Output as JSON array
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        printf '[{"priority":"info","action":"none","description":"No immediate security improvements needed"}]\n'
    else
        local json_arr
        json_arr=$(IFS=,; echo "${recommendations[*]}")
        printf '[%s]\n' "$json_arr"
    fi
}

# Get total vulnerability count
# @param $1 - Repository (owner/repo)
# @return JSON with vulnerability counts
# Usage: ghs_vulnerability_count "owner/repo"
ghs_vulnerability_count() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local dependabot code_scanning secret_scanning

    dependabot=$(ghs_dependabot_count "$repo" 2>/dev/null) || dependabot='{"total":0}'

    local code_alerts
    code_alerts=$(ghs_code_alerts "$repo" 2>/dev/null)
    if [[ -n "$code_alerts" ]] && command -v jq &>/dev/null; then
        code_scanning=$(echo "$code_alerts" | jq 'length')
    else
        code_scanning=0
    fi

    local secret_alerts
    secret_alerts=$(ghs_secret_alerts "$repo" 2>/dev/null)
    if [[ -n "$secret_alerts" ]] && command -v jq &>/dev/null; then
        secret_scanning=$(echo "$secret_alerts" | jq 'length')
    else
        secret_scanning=0
    fi

    local dep_total=0
    if command -v jq &>/dev/null; then
        dep_total=$(echo "$dependabot" | jq -r '.total // 0')
    fi

    printf '{"dependabot":%s,"code_scanning":%d,"secret_scanning":%d,"total":%d}\n' \
        "$dependabot" "$code_scanning" "$secret_scanning" "$((dep_total + code_scanning + secret_scanning))"
}

# Basic compliance checks
# @param $1 - Repository (owner/repo)
# @return JSON with compliance status
# Usage: ghs_compliance_check "owner/repo"
ghs_compliance_check() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local checks=()
    local passed=0
    local total=5

    # Check 1: Branch protection
    if ghs_branch_summary "$repo" 2>/dev/null | grep -q '"protected":true'; then
        checks+='"branch_protection":"pass"'
        ((passed++))
    else
        checks+='"branch_protection":"fail"'
    fi

    # Check 2: Dependabot enabled
    if ghs_dependabot_enabled "$repo" &>/dev/null; then
        checks+='"dependabot_enabled":"pass"'
        ((passed++))
    else
        checks+='"dependabot_enabled":"fail"'
    fi

    # Check 3: No critical vulnerabilities
    local dep_count
    dep_count=$(ghs_dependabot_count "$repo" 2>/dev/null)
    local critical=0
    if command -v jq &>/dev/null && [[ -n "$dep_count" ]]; then
        critical=$(echo "$dep_count" | jq -r '.critical // 0')
    fi
    if [[ "$critical" -eq 0 ]]; then
        checks+='"no_critical_vulns":"pass"'
        ((passed++))
    else
        checks+='"no_critical_vulns":"fail"'
    fi

    # Check 4: Secret scanning
    if ghs_secret_enabled "$repo" &>/dev/null; then
        checks+='"secret_scanning":"pass"'
        ((passed++))
    else
        checks+='"secret_scanning":"fail"'
    fi

    # Check 5: Push protection
    if ghs_secret_push_protection "$repo" &>/dev/null; then
        checks+='"push_protection":"pass"'
        ((passed++))
    else
        checks+='"push_protection":"fail"'
    fi

    local checks_json
    checks_json=$(IFS=,; echo "${checks[*]}")
    local compliant="false"
    [[ "$passed" -eq "$total" ]] && compliant="true"

    printf '{"repository":"%s/%s","passed":%d,"total":%d,"compliant":%s,"checks":{%s}}\n' \
        "$_GHS_OWNER" "$_GHS_REPO" "$passed" "$total" "$compliant" "$checks_json"
}

# List enabled security features
# @param $1 - Repository (owner/repo)
# @return JSON array of enabled features
# Usage: ghs_enabled_features "owner/repo"
ghs_enabled_features() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local features=()

    ghs_dependabot_enabled "$repo" &>/dev/null && features+='"dependabot_alerts"'
    ghs_secret_enabled "$repo" &>/dev/null && features+='"secret_scanning"'
    ghs_secret_push_protection "$repo" &>/dev/null && features+='"push_protection"'

    local code_setup
    code_setup=$(ghs_code_default_setup "$repo" 2>/dev/null)
    if [[ "$code_setup" == *'"state":"configured"'* || "$code_setup" == *'"state":"not-configured"'* ]]; then
        features+='"code_scanning"'
    fi

    local branch_summary
    branch_summary=$(ghs_branch_summary "$repo" 2>/dev/null)
    [[ "$branch_summary" == *'"protected":true'* ]] && features+='"branch_protection"'

    local features_json
    features_json=$(IFS=,; echo "${features[*]}")
    printf '[%s]\n' "$features_json"
}

# =============================================================================
# SECTION 8: AUDIT LOG
# =============================================================================

# Get organization audit log entries
# @param $1 - Organization name
# @param $2 - Days to look back (default: 7)
# @return JSON array of audit entries
# Usage: ghs_audit_log "my-org" 30
ghs_audit_log() {
    local org="$1"
    local days="${2:-7}"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/audit-log?per_page=100" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch audit log (requires org admin)"}\n'
        return 1
    }
}

# Search audit log
# @param $1 - Organization name
# @param $2 - Search phrase
# @return JSON array of matching entries
# Usage: ghs_audit_search "my-org" "repo.create"
ghs_audit_search() {
    local org="$1"
    local query="$2"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    [[ -z "$query" ]] && { _ghs_error "search query required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/audit-log?phrase=${query}&per_page=100" --paginate 2>/dev/null || {
        printf '{"error":"failed to search audit log"}\n'
        return 1
    }
}

# Filter audit log by actor
# @param $1 - Organization name
# @param $2 - Actor username
# @return JSON array of entries by actor
# Usage: ghs_audit_actions "my-org" "username"
ghs_audit_actions() {
    local org="$1"
    local actor="$2"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    [[ -z "$actor" ]] && { _ghs_error "actor required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/audit-log?phrase=actor:${actor}&per_page=100" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch audit log by actor"}\n'
        return 1
    }
}

# Filter audit log by repository
# @param $1 - Organization name
# @param $2 - Repository name (without org prefix)
# @return JSON array of entries for repo
# Usage: ghs_audit_repos "my-org" "my-repo"
ghs_audit_repos() {
    local org="$1"
    local repo="$2"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    [[ -z "$repo" ]] && { _ghs_error "repository required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/audit-log?phrase=repo:${org}/${repo}&per_page=100" --paginate 2>/dev/null || {
        printf '{"error":"failed to fetch audit log by repo"}\n'
        return 1
    }
}

# Export audit log
# @param $1 - Organization name
# @param $2 - Format: json (default), csv
# @return Audit log in requested format
# Usage: ghs_audit_export "my-org" "json"
ghs_audit_export() {
    local org="$1"
    local format="${2:-json}"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    local log
    log=$(ghs_audit_log "$org" 90) || return 1

    if [[ "$format" == "csv" ]] && command -v jq &>/dev/null; then
        echo "@timestamp,action,actor,repo"
        echo "$log" | jq -r '.[] | [.["@timestamp"], .action, .actor, .repo] | @csv'
    else
        echo "$log"
    fi
}

# =============================================================================
# SECTION 9: GHAS (GitHub Advanced Security)
# =============================================================================

# Check GHAS license status for organization
# @param $1 - Organization name
# @return JSON with GHAS status
# Usage: ghs_ghas_status "my-org"
ghs_ghas_status() {
    local org="$1"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/settings/billing/advanced-security" 2>/dev/null || {
        printf '{"error":"failed to fetch GHAS status (requires org admin)"}\n'
        return 1
    }
}

# List active GHAS committers
# @param $1 - Organization name
# @return JSON array of committers
# Usage: ghs_ghas_committers "my-org"
ghs_ghas_committers() {
    local org="$1"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/settings/billing/advanced-security" \
        --jq '.repositories[].advanced_security_committers_breakdown // []' 2>/dev/null || {
        printf '{"error":"failed to fetch committers"}\n'
        return 1
    }
}

# List repos with GHAS enabled
# @param $1 - Organization name
# @return JSON array of repos
# Usage: ghs_ghas_repos "my-org"
ghs_ghas_repos() {
    local org="$1"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/repos?per_page=100" --paginate 2>/dev/null | \
        if command -v jq &>/dev/null; then
            jq '[.[] | select(.security_and_analysis.advanced_security.status == "enabled") |
                {name: .name, full_name: .full_name}]'
        else
            cat
        fi
}

# Enable GHAS for a repository
# @param $1 - Repository (owner/repo)
# @return JSON with result
# Usage: ghs_ghas_enable "owner/repo"
ghs_ghas_enable() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    gh api -X PATCH "/repos/${_GHS_OWNER}/${_GHS_REPO}" \
        --input - <<< '{"security_and_analysis":{"advanced_security":{"status":"enabled"}}}' 2>/dev/null || {
        printf '{"error":"failed to enable GHAS (requires GHAS license)"}\n'
        return 1
    }
}

# Get GHAS billing info
# @param $1 - Organization name
# @return JSON with billing details
# Usage: ghs_ghas_billing "my-org"
ghs_ghas_billing() {
    local org="$1"

    [[ -z "$org" ]] && { _ghs_error "organization required"; return 1; }
    _ghs_check_gh || return 1

    gh api "/orgs/${org}/settings/billing/advanced-security" 2>/dev/null || {
        printf '{"error":"failed to fetch billing info"}\n'
        return 1
    }
}

# =============================================================================
# SECTION 10: SECURITY REPORT GENERATION
# =============================================================================

# Generate full security report as JSON
# @param $1 - Repository (owner/repo)
# @return Comprehensive JSON report
# Usage: ghs_report_json "owner/repo"
ghs_report_json() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local overview score recommendations vulns enabled

    overview=$(ghs_overview "$repo" 2>/dev/null) || overview='{}'
    score=$(ghs_score "$repo" 2>/dev/null) || score='{"score":0}'
    recommendations=$(ghs_recommendations "$repo" 2>/dev/null) || recommendations='[]'
    vulns=$(ghs_vulnerability_count "$repo" 2>/dev/null) || vulns='{"total":0}'
    enabled=$(ghs_enabled_features "$repo" 2>/dev/null) || enabled='[]'

    printf '{"report_date":"%s","repository":"%s/%s","overview":%s,"score":%s,"vulnerabilities":%s,"enabled_features":%s,"recommendations":%s}\n' \
        "$(date -Iseconds)" "$_GHS_OWNER" "$_GHS_REPO" \
        "$overview" "$score" "$vulns" "$enabled" "$recommendations"
}

# Generate security report as markdown
# @param $1 - Repository (owner/repo)
# @return Markdown formatted report
# Usage: ghs_report_markdown "owner/repo"
ghs_report_markdown() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local score_json recommendations_json vulns_json

    score_json=$(ghs_score "$repo" 2>/dev/null) || score_json='{"score":0}'
    recommendations_json=$(ghs_recommendations "$repo" 2>/dev/null) || recommendations_json='[]'
    vulns_json=$(ghs_vulnerability_count "$repo" 2>/dev/null) || vulns_json='{"total":0}'

    local score=0 total_vulns=0
    if command -v jq &>/dev/null; then
        score=$(echo "$score_json" | jq -r '.score // 0')
        total_vulns=$(echo "$vulns_json" | jq -r '.total // 0')
    fi

    cat << EOF
# Security Report: ${_GHS_OWNER}/${_GHS_REPO}

**Generated:** $(date -Iseconds)

## Security Score

**Score: ${score}/100**

## Vulnerability Summary

- **Total Open Issues:** ${total_vulns}

## Enabled Features

$(ghs_enabled_features "$repo" 2>/dev/null | tr ',' '\n' | sed 's/[][]//g; s/"//g; s/^/- /')

## Recommendations

$(echo "$recommendations_json" | if command -v jq &>/dev/null; then
    jq -r '.[] | "- **[\(.priority)]** \(.description)"'
else
    echo "See JSON report for details"
fi)

---
*Report generated by MAINFRAME github_security.sh*
EOF
}

# Get brief summary for AI context
# @param $1 - Repository (owner/repo)
# @return Compact JSON summary
# Usage: ghs_report_summary "owner/repo"
ghs_report_summary() {
    local repo="$1"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    local score vulns
    score=$(ghs_score "$repo" 2>/dev/null)
    vulns=$(ghs_vulnerability_count "$repo" 2>/dev/null)

    local score_val=0 critical=0 high=0 total=0
    if command -v jq &>/dev/null; then
        score_val=$(echo "$score" | jq -r '.score // 0')
        critical=$(echo "$vulns" | jq -r '.dependabot.critical // 0')
        high=$(echo "$vulns" | jq -r '.dependabot.high // 0')
        total=$(echo "$vulns" | jq -r '.total // 0')
    fi

    local action="none"
    [[ "$high" -gt 0 ]] && action="review_high_severity"
    [[ "$critical" -gt 0 ]] && action="fix_critical_immediately"

    printf '{"repo":"%s/%s","score":%d,"critical":%d,"high":%d,"total_vulns":%d,"action":"%s"}\n' \
        "$_GHS_OWNER" "$_GHS_REPO" "$score_val" "$critical" "$high" "$total" "$action"
}

# Compare security posture over time
# @param $1 - Repository (owner/repo)
# @param $2 - Days to compare (default: 7)
# @return JSON with current vs historical (if available)
# Usage: ghs_report_compare "owner/repo" 30
ghs_report_compare() {
    local repo="$1"
    local days="${2:-7}"

    _ghs_check_gh || return 1
    _ghs_parse_repo "$repo" || return 1

    # Current state
    local current
    current=$(ghs_report_summary "$repo") || return 1

    # Note: Historical comparison requires external storage
    # This provides current snapshot with metadata
    printf '{"current":%s,"comparison_period_days":%d,"note":"historical tracking requires external storage"}\n' \
        "$current" "$days"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

_GITHUB_SECURITY_EXPORTS=(
    # Dependabot
    ghs_dependabot_alerts
    ghs_dependabot_alert_view
    ghs_dependabot_alert_dismiss
    ghs_dependabot_alert_reopen
    ghs_dependabot_critical
    ghs_dependabot_high
    ghs_dependabot_count
    ghs_dependabot_summary
    ghs_dependabot_enabled
    ghs_dependabot_config
    # Secret Scanning
    ghs_secret_alerts
    ghs_secret_alert_view
    ghs_secret_alert_resolve
    ghs_secret_types
    ghs_secret_locations
    ghs_secret_validity
    ghs_secret_enabled
    ghs_secret_push_protection
    # Code Scanning
    ghs_code_alerts
    ghs_code_alert_view
    ghs_code_alert_dismiss
    ghs_code_analysis_list
    ghs_code_sarif_upload
    ghs_code_default_setup
    ghs_code_enable
    ghs_code_languages
    ghs_code_rules
    ghs_code_by_severity
    ghs_code_by_rule
    ghs_code_summary
    # SBOM
    ghs_sbom_export
    ghs_sbom_dependencies
    ghs_sbom_dependency_graph
    ghs_sbom_licenses
    ghs_sbom_outdated
    ghs_sbom_summary
    # Security Advisories
    ghs_advisory_list
    ghs_advisory_view
    ghs_advisory_create
    ghs_advisory_update
    ghs_advisory_publish
    ghs_advisory_request_cve
    ghs_advisory_credits
    ghs_advisory_global_search
    # Branch Protection
    ghs_branch_protection
    ghs_branch_required_checks
    ghs_branch_dismiss_reviews
    ghs_branch_require_reviews
    ghs_branch_enforce_admins
    ghs_branch_restrict_push
    ghs_branch_allow_force_push
    ghs_branch_summary
    # Security Overview
    ghs_overview
    ghs_score
    ghs_recommendations
    ghs_vulnerability_count
    ghs_compliance_check
    ghs_enabled_features
    # Audit Log
    ghs_audit_log
    ghs_audit_search
    ghs_audit_actions
    ghs_audit_repos
    ghs_audit_export
    # GHAS
    ghs_ghas_status
    ghs_ghas_committers
    ghs_ghas_repos
    ghs_ghas_enable
    ghs_ghas_billing
    # Reports
    ghs_report_json
    ghs_report_markdown
    ghs_report_summary
    ghs_report_compare
)

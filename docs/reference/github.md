# GitHub Functions

GitHub API, Actions, and Security integration via `gh` CLI.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## GitHub CLI Integration (github.sh)

### Authentication

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_auth_status` | `gh_auth_status` | `gh_auth_status && echo "logged in"` | 0=authenticated |
| `gh_auth_token` | `gh_auth_token` | `token=$(gh_auth_token)` | Auth token (masked) |
| `gh_whoami` | `gh_whoami` | `user=$(gh_whoami)` | Current username |
| `gh_config_get` | `gh_config_get "key"` | `gh_config_get "git_protocol"` | Config value |
| `gh_config_set` | `gh_config_set "key" "value"` | `gh_config_set "editor" "vim"` | Sets config |

### Repository Operations

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_repo_view` | `gh_repo_view "owner/repo"` | `gh_repo_view "anthropics/claude"` | JSON repo info |
| `gh_repo_list` | `gh_repo_list "owner" [limit]` | `gh_repo_list "anthropics" 50` | JSON array of repos |
| `gh_repo_create` | `gh_repo_create "name" [--public\|--private]` | `gh_repo_create "my-app" --public` | Creates repo |
| `gh_repo_clone` | `gh_repo_clone "owner/repo" [dir]` | `gh_repo_clone "owner/repo" ./local` | Clones repo |
| `gh_repo_fork` | `gh_repo_fork "owner/repo"` | `gh_repo_fork "anthropics/claude"` | Forks repo |
| `gh_repo_exists` | `gh_repo_exists "owner/repo"` | `gh_repo_exists "owner/repo" && echo "yes"` | 0=exists |
| `gh_repo_default_branch` | `gh_repo_default_branch "owner/repo"` | `branch=$(gh_repo_default_branch "owner/repo")` | Branch name |
| `gh_repo_stars` | `gh_repo_stars "owner/repo"` | `count=$(gh_repo_stars "owner/repo")` | Star count |
| `gh_repo_visibility` | `gh_repo_visibility "owner/repo"` | `gh_repo_visibility "owner/repo"` | public/private |

### Issues

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_issue_list` | `gh_issue_list "repo" [--state open\|closed\|all]` | `gh_issue_list "owner/repo" --state open` | JSON issues |
| `gh_issue_create` | `gh_issue_create "repo" "title" "body"` | `gh_issue_create "repo" "Bug" "Desc"` | Issue URL |
| `gh_issue_view` | `gh_issue_view "repo" number` | `gh_issue_view "repo" 42` | JSON issue details |
| `gh_issue_close` | `gh_issue_close "repo" number` | `gh_issue_close "repo" 42` | Closes issue |
| `gh_issue_reopen` | `gh_issue_reopen "repo" number` | `gh_issue_reopen "repo" 42` | Reopens issue |
| `gh_issue_comment` | `gh_issue_comment "repo" number "body"` | `gh_issue_comment "repo" 42 "Fixed!"` | Adds comment |
| `gh_issue_search` | `gh_issue_search "query"` | `gh_issue_search "is:open label:bug"` | JSON results |

### Pull Requests

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_pr_list` | `gh_pr_list "repo" [--state open\|closed\|merged]` | `gh_pr_list "repo" --state open` | JSON PRs |
| `gh_pr_create` | `gh_pr_create "repo" "title" --body "body"` | `gh_pr_create "repo" "Feature" --body "Adds X"` | PR URL |
| `gh_pr_view` | `gh_pr_view "repo" number` | `gh_pr_view "repo" 123` | JSON PR details |
| `gh_pr_diff` | `gh_pr_diff "repo" number` | `gh_pr_diff "repo" 123` | Unified diff |
| `gh_pr_files` | `gh_pr_files "repo" number` | `gh_pr_files "repo" 123` | JSON changed files |
| `gh_pr_merge` | `gh_pr_merge "repo" number [--squash\|--rebase]` | `gh_pr_merge "repo" 123 --squash` | Merges PR |
| `gh_pr_close` | `gh_pr_close "repo" number` | `gh_pr_close "repo" 123` | Closes PR |
| `gh_pr_review` | `gh_pr_review "repo" number [--approve\|--request-changes]` | `gh_pr_review "repo" 123 --approve` | Submits review |
| `gh_pr_checks` | `gh_pr_checks "repo" number` | `gh_pr_checks "repo" 123` | JSON CI status |
| `gh_pr_is_merged` | `gh_pr_is_merged "repo" number` | `gh_pr_is_merged "repo" 123 && echo "yes"` | 0=merged |

### Releases

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_release_list` | `gh_release_list "repo" [limit]` | `gh_release_list "repo" 10` | JSON releases |
| `gh_release_latest` | `gh_release_latest "repo"` | `gh_release_latest "repo"` | JSON latest release |
| `gh_release_create` | `gh_release_create "repo" "tag" --title "title"` | `gh_release_create "repo" "v1.0" --title "v1.0"` | Creates release |
| `gh_release_download` | `gh_release_download "repo" "tag" [pattern]` | `gh_release_download "repo" "v1.0" "*.tar.gz"` | Downloads assets |

### Search

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_search_repos` | `gh_search_repos "query" [limit]` | `gh_search_repos "language:rust stars:>1000"` | JSON repos |
| `gh_search_code` | `gh_search_code "query" [limit]` | `gh_search_code "filename:package.json"` | JSON code results |
| `gh_search_issues` | `gh_search_issues "query" [limit]` | `gh_search_issues "is:open label:bug"` | JSON issues |

### AI Agent Context Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gh_context_json` | `gh_context_json "owner/repo"` | `gh_context_json "anthropics/claude"` | Full repo context JSON |
| `gh_pr_context` | `gh_pr_context "owner/repo" number` | `gh_pr_context "repo" 123` | PR context with diff stats |
| `gh_issue_context` | `gh_issue_context "owner/repo" number` | `gh_issue_context "repo" 42` | Issue + comments JSON |
| `gh_repo_summary` | `gh_repo_summary "owner/repo"` | `gh_repo_summary "repo"` | Compact summary string |
| `gh_repo_tree` | `gh_repo_tree "owner/repo" [path] [depth]` | `gh_repo_tree "repo" "src" 3` | File tree JSON |
| `gh_recent_commits` | `gh_recent_commits "owner/repo" [limit]` | `gh_recent_commits "repo" 10` | Recent commits JSON |

---

## GitHub Actions (github_actions.sh)

### Workflow Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gha_workflow_list` | `gha_workflow_list "repo"` | `gha_workflow_list "owner/repo"` | JSON workflows |
| `gha_workflow_runs` | `gha_workflow_runs "repo" "workflow"` | `gha_workflow_runs "repo" "ci.yml"` | JSON runs |
| `gha_workflow_run` | `gha_workflow_run "repo" "workflow" [ref]` | `gha_workflow_run "repo" "deploy.yml" "main"` | Triggers workflow |

### Run Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gha_run_view` | `gha_run_view "repo" run_id` | `gha_run_view "repo" 9876543` | JSON run details |
| `gha_run_logs` | `gha_run_logs "repo" run_id` | `gha_run_logs "repo" 9876543` | Download logs |
| `gha_run_cancel` | `gha_run_cancel "repo" run_id` | `gha_run_cancel "repo" 9876543` | Cancels run |
| `gha_run_rerun` | `gha_run_rerun "repo" run_id` | `gha_run_rerun "repo" 9876543` | Re-runs workflow |
| `gha_run_status` | `gha_run_status "repo" run_id` | `gha_run_status "repo" 9876543` | queued/in_progress/completed |
| `gha_run_conclusion` | `gha_run_conclusion "repo" run_id` | `gha_run_conclusion "repo" 9876543` | success/failure/cancelled |
| `gha_run_wait` | `gha_run_wait "repo" run_id [timeout]` | `gha_run_wait "repo" 9876543 600` | Waits for completion |

### Secrets & Variables

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gha_secret_list` | `gha_secret_list "repo"` | `gha_secret_list "owner/repo"` | JSON secret names |
| `gha_secret_set` | `gha_secret_set "repo" "name" "value"` | `gha_secret_set "repo" "API_KEY" "xxx"` | Sets secret |
| `gha_secret_delete` | `gha_secret_delete "repo" "name"` | `gha_secret_delete "repo" "OLD_KEY"` | Deletes secret |
| `gha_variable_list` | `gha_variable_list "repo"` | `gha_variable_list "owner/repo"` | JSON variables |
| `gha_variable_set` | `gha_variable_set "repo" "name" "value"` | `gha_variable_set "repo" "ENV" "prod"` | Sets variable |

### CI Status

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `gha_is_passing` | `gha_is_passing "repo"` | `gha_is_passing "repo" && echo "green"` | 0=passing |
| `gha_last_success` | `gha_last_success "repo" "workflow"` | `gha_last_success "repo" "ci.yml"` | Last success JSON |
| `gha_failure_rate` | `gha_failure_rate "repo" "workflow" days` | `gha_failure_rate "repo" "ci.yml" 30` | Failure percentage |
| `gha_context_json` | `gha_context_json "repo"` | `gha_context_json "owner/repo"` | Full CI context JSON |

---

## GitHub Security (github_security.sh)

### Dependabot Alerts

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ghs_dependabot_alerts` | `ghs_dependabot_alerts "repo" [state]` | `ghs_dependabot_alerts "repo" "open"` | JSON alerts |
| `ghs_dependabot_critical` | `ghs_dependabot_critical "repo"` | `ghs_dependabot_critical "repo"` | Critical alerts only |
| `ghs_dependabot_count` | `ghs_dependabot_count "repo"` | `ghs_dependabot_count "repo"` | Count by severity |
| `ghs_dependabot_summary` | `ghs_dependabot_summary "repo"` | `ghs_dependabot_summary "repo"` | AI-friendly summary |

### Secret Scanning

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ghs_secret_alerts` | `ghs_secret_alerts "repo" [state]` | `ghs_secret_alerts "repo" "open"` | JSON secret alerts |
| `ghs_secret_alert_resolve` | `ghs_secret_alert_resolve "repo" id "resolution"` | `ghs_secret_alert_resolve "repo" 15 "revoked"` | Resolves alert |
| `ghs_secret_enabled` | `ghs_secret_enabled "repo"` | `ghs_secret_enabled "repo" && echo "yes"` | 0=enabled |

### Code Scanning (CodeQL)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ghs_code_alerts` | `ghs_code_alerts "repo" [state]` | `ghs_code_alerts "repo" "open"` | JSON code alerts |
| `ghs_code_sarif_upload` | `ghs_code_sarif_upload "repo" file ref` | `ghs_code_sarif_upload "repo" results.sarif "main"` | Uploads SARIF |
| `ghs_code_summary` | `ghs_code_summary "repo"` | `ghs_code_summary "repo"` | AI-friendly summary |

### Security Overview

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `ghs_overview` | `ghs_overview "repo"` | `ghs_overview "owner/repo"` | Full security JSON |
| `ghs_score` | `ghs_score "repo"` | `score=$(ghs_score "repo")` | Security score 0-100 |
| `ghs_recommendations` | `ghs_recommendations "repo"` | `ghs_recommendations "repo"` | AI recommendations |
| `ghs_vulnerability_count` | `ghs_vulnerability_count "repo"` | `ghs_vulnerability_count "repo"` | Total vuln count |
| `ghs_report_markdown` | `ghs_report_markdown "repo"` | `ghs_report_markdown "repo"` | Markdown report |

---

## Quick Patterns

### Check CI Status
```bash
if gha_is_passing "owner/repo"; then
    echo "CI is green, safe to deploy"
    gha_workflow_run "owner/repo" "deploy.yml" "main"
fi
```

### Security Review
```bash
# Get security score
score=$(ghs_score "owner/repo")
echo "Security score: $score/100"

# Check for critical vulnerabilities
critical=$(ghs_dependabot_critical "owner/repo")
if [[ -n "$critical" ]]; then
    echo "Critical vulnerabilities found!"
fi
```

### PR Workflow
```bash
# Create PR
gh_pr_create "owner/repo" "Feature: Add login" --body "Implements OAuth login"

# Wait for CI
gha_run_wait "owner/repo" "$run_id" 600

# Merge if passing
if gha_is_passing "owner/repo"; then
    gh_pr_merge "owner/repo" 123 --squash
fi
```

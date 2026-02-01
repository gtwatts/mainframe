# Git Functions

Git repository operations.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Git Functions (git.sh)

### Repository Status

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_is_repo` | `git_is_repo` | `git_is_repo && echo "yes"` | (returns 0/1) |
| `git_root` | `git_root` | `git_root` | `/path/to/repo` |
| `git_branch` | `git_branch` | `git_branch` | `main` |
| `git_branches` | `git_branches` | `git_branches` | List of branches |
| `git_default_branch` | `git_default_branch` | `git_default_branch` | `main` or `master` |
| `git_is_dirty` | `git_is_dirty` | `git_is_dirty && echo "uncommitted"` | (returns 0/1) |
| `git_is_clean` | `git_is_clean` | `git_is_clean && git push` | (returns 0/1) |
| `git_has_staged` | `git_has_staged` | `git_has_staged` | (returns 0/1) |
| `git_has_unstaged` | `git_has_unstaged` | `git_has_unstaged` | (returns 0/1) |
| `git_has_untracked` | `git_has_untracked` | `git_has_untracked` | (returns 0/1) |
| `git_files_changed` | `git_files_changed` | `git_files_changed` | List of files |

### Commit Information

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_commit_hash` | `git_commit_hash` | `git_commit_hash` | `abc1234` |
| `git_commit_hash_full` | `git_commit_hash_full` | `git_commit_hash_full` | Full 40-char hash |
| `git_commit_message` | `git_commit_message` | `git_commit_message` | Latest message |
| `git_commit_author` | `git_commit_author` | `git_commit_author` | `John Doe` |
| `git_commit_count` | `git_commit_count` | `git_commit_count` | `42` |
| `git_commits_ahead` | `git_commits_ahead` | `git_commits_ahead` | `3` |
| `git_commits_behind` | `git_commits_behind` | `git_commits_behind` | `0` |
| `git_log_oneline` | `git_log_oneline [n]` | `git_log_oneline 5` | Last 5 commits |
| `git_changed_since` | `git_changed_since "ref"` | `git_changed_since "HEAD~5"` | Changed files |

### Tags

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_tag_latest` | `git_tag_latest` | `git_tag_latest` | `v1.2.3` |
| `git_tags` | `git_tags` | `git_tags` | List of tags |
| `git_tag_exists` | `git_tag_exists "tag"` | `git_tag_exists "v1.0.0"` | (returns 0/1) |
| `git_describe` | `git_describe` | `git_describe` | `v1.2.3-4-gabc1234` |

### Remote

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_remote_url` | `git_remote_url` | `git_remote_url` | `git@github.com:...` |
| `git_has_remote` | `git_has_remote` | `git_has_remote` | (returns 0/1) |
| `git_is_pushed` | `git_is_pushed` | `git_is_pushed` | (returns 0/1) |

### User Config

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_user_name` | `git_user_name` | `git_user_name` | Configured name |
| `git_user_email` | `git_user_email` | `git_user_email` | Configured email |

### Summary

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_summary` | `git_summary` | `git_summary` | `main @ abc1234 [clean]` |

---

## Enhanced Git Functions (Repository & Provider Info)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `git_repo_name` | `git_repo_name` | `git_repo_name` | `mainframe` (from URL) |
| `git_repo_url` | `git_repo_url [remote]` | `git_repo_url upstream` | Full remote URL |
| `git_repo_owner` | `git_repo_owner` | `git_repo_owner` | `gtwatts` (from URL) |
| `git_provider` | `git_provider` | `git_provider` | `github`, `gitlab`, `bitbucket`, `azure`, `codeberg`, `unknown` |
| `git_web_url` | `git_web_url` | `git_web_url` | `https://github.com/user/repo` |
| `git_upstream_branch` | `git_upstream_branch` | `git_upstream_branch` | `origin/main` |
| `git_remotes_json` | `git_remotes_json` | `git_remotes_json` | `[{"name":"origin","fetch_url":"...","push_url":"..."}]` |
| `git_changed_files` | `git_changed_files [filter]` | `git_changed_files staged` | Newline-separated paths |
| `git_last_commit` | `git_last_commit` | `git_last_commit` | `{"hash":"abc123","author":"name","date":"ISO","message":"..."}` |
| `git_summary_json` | `git_summary_json` | `git_summary_json` | Full repo status as JSON |

**git_changed_files filter options:**
- `staged` - Only staged files
- `unstaged` - Only modified but not staged
- `untracked` - Only untracked files
- `all` (default) - All changed files (unique)

### git_summary_json Output
```json
{
  "branch": "main",
  "commit_hash": "abc1234",
  "commit_count": 42,
  "is_dirty": false,
  "has_staged": false,
  "has_unstaged": false,
  "has_untracked": false,
  "remote_url": "https://github.com/user/repo.git",
  "provider": "github",
  "owner": "user",
  "repo_name": "repo",
  "tag_latest": "v1.2.3"
}
```

---

## Quick Patterns

### Git Workflow Check
```bash
if git_is_dirty; then
    echo "Uncommitted changes in $(git_branch)"
    echo "Files: $(git_files_changed)"
fi
echo "$(git_summary)"  # main @ abc1234 [clean]
```

### Pre-Commit Checks
```bash
if git_is_repo && git_has_staged; then
    # Run linters on staged files only
    git_changed_files staged | xargs eslint
fi
```

### Release Workflow
```bash
current_tag=$(git_tag_latest)
echo "Current release: $current_tag"
echo "Commits since: $(git_commit_count)"
```

### Provider Detection
```bash
case "$(git_provider)" in
    github)
        echo "Using GitHub"
        ;;
    gitlab)
        echo "Using GitLab"
        ;;
    *)
        echo "Unknown provider"
        ;;
esac
```

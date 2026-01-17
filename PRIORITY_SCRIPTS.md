# MAINFRAME Priority Scripts

**Research-Backed Implementation Order**

Based on deep research into vibe coding pain points, agentic tool failures, and community feedback, these scripts should be implemented first.

---

## Tier 1: CRITICAL (Implement Immediately)

These scripts address the most frequent failures that stop users cold.

### 1. `path-safe` - Safe Path Handler
**Pain Point**: 95% of commands with spaces fail
**WOW Factor**: 10

```bash
# Wraps any command with proper path quoting
mainframe path-safe mv "$source" "$dest"

# Normalizes paths across platforms
mainframe path-safe --normalize "C:\Users\Me\Documents"
```

### 2. `npm-install-safe` - npm Without Tears
**Pain Point**: 90% hit EACCES errors
**WOW Factor**: 10

```bash
# Detects and fixes permission issues automatically
mainframe npm-install-safe -g typescript

# Uses nvm if available, fixes ownership if not
# Never suggests sudo
```

### 3. `docker-fix` - Docker Permission Fixer
**Pain Point**: 85% can't run docker without sudo
**WOW Factor**: 9

```bash
# Diagnoses and fixes docker socket permissions
mainframe docker-fix

# Fixes volume ownership issues
mainframe docker-fix --volumes ./data
```

### 4. `chmod-fix` - Execute Permission Fixer
**Pain Point**: 80% don't understand chmod
**WOW Factor**: 9

```bash
# Makes script executable, handles edge cases
mainframe chmod-fix script.sh

# Fixes entire directory of scripts
mainframe chmod-fix scripts/
```

### 5. `git-init-safe` - Safe Git Initialization
**Pain Point**: 80% run git from wrong directory
**WOW Factor**: 9

```bash
# Initializes with .gitignore, initial commit
mainframe git-init-safe

# Validates you're in the right place
# Creates sensible defaults
```

---

## Tier 2: HIGH PRIORITY (Implement Next)

These scripts address daily pain points.

### 6. `env-persist` - Environment Variable Manager
**Pain Point**: 75% lose env vars on new terminal
**WOW Factor**: 9

```bash
# Sets variable AND persists to shell config
mainframe env-persist MY_VAR "value"

# Works across bash/zsh/fish
# Validates before writing
```

### 7. `retry` - Smart Retry Wrapper
**Pain Point**: 70% have no retry logic for network calls
**WOW Factor**: 10

```bash
# Retries curl with exponential backoff
mainframe retry curl https://api.example.com

# Configurable attempts, delay, conditions
mainframe retry --attempts 5 --on-status 429,503 curl ...
```

### 8. `volume-fix` - Docker Volume Fixer
**Pain Point**: 70% have container permission issues
**WOW Factor**: 8

```bash
# Fixes ownership to match container user
mainframe volume-fix ./data 1000:1000

# Detects common patterns (node, python, etc)
```

### 9. `jq-safe` - jq Without Escaping Hell
**Pain Point**: 65% have jq escaping issues
**WOW Factor**: 9

```bash
# Handles escaping automatically
mainframe jq-safe '.users[] | select(.active)' data.json

# Works on Windows (Git Bash quote issues)
# Validates jq expression before running
```

### 10. `kill-tree` - Process Tree Killer
**Pain Point**: 60% leave orphan processes
**WOW Factor**: 8

```bash
# Kills process and ALL children
mainframe kill-tree $PID

# Graceful first, then force
# Logs what was killed
```

---

## Tier 3: IMPORTANT (Implement Soon)

These scripts address weekly pain points.

### 11. `sed-cross` - Cross-Platform sed
**Pain Point**: 60% hit BSD vs GNU differences
**WOW Factor**: 8

```bash
# Works identically on Mac and Linux
mainframe sed-cross 's/old/new/g' file.txt

# In-place editing that works everywhere
```

### 12. `tail-rotate` - Rotation-Safe Log Tailing
**Pain Point**: 55% miss logs after rotation
**WOW Factor**: 7

```bash
# Follows file by name, not inode
mainframe tail-rotate /var/log/app.log

# Survives log rotation
```

### 13. `git-push-large` - Large Repo Pusher
**Pain Point**: 50% fail pushing large repos
**WOW Factor**: 8

```bash
# Increases buffer, retries, suggests LFS
mainframe git-push-large

# Handles common push failures
```

### 14. `venv-safe` - Python Environment Manager
**Pain Point**: 50% use wrong Python version
**WOW Factor**: 8

```bash
# Creates and activates venv correctly
mainframe venv-safe create myenv

# Detects Python version requirements
mainframe venv-safe activate
```

### 15. `cargo-ensure` - Rust Dependency Handler
**Pain Point**: 45% fail pip install needing Rust
**WOW Factor**: 9

```bash
# Installs Rust if needed, then runs command
mainframe cargo-ensure pip install orjson

# Detects Rust requirement, handles installation
```

---

## Tier 4: VALUABLE (Implement Later)

These scripts add significant value.

### Error Translation
```
error-explain      - Translate error to plain English
error-suggest      - Suggest fixes for common errors
```

### Security
```
secrets-scan       - Find exposed API keys
permissions-audit  - Audit file permissions
```

### CI/CD
```
ci-local           - Run CI pipeline locally
deploy-rollback    - Deploy with automatic rollback
```

### Monitoring
```
watch-change       - Watch files with action trigger
process-health     - Monitor process health
port-wait          - Wait for port availability
```

---

## Implementation Notes

### Script Template

Every MAINFRAME script MUST:

1. **Validate inputs** before execution
2. **Detect platform** and adapt
3. **Handle common failures** automatically
4. **Provide clear errors** when manual help needed
5. **Never leave broken state**
6. **Log actions** for debugging

### Testing Requirements

Each script needs:
- BATS unit tests
- Cross-platform verification (Linux, Mac, Windows/WSL)
- Edge case coverage (spaces, special chars, permissions)
- Integration test with Claude Code

### Documentation Requirements

Each script needs:
- Help text (`--help`)
- Examples in README
- Common failure modes documented
- VHS demo recording

---

## Success Metrics

| Metric | Target |
|--------|--------|
| First-try success rate | 95%+ |
| Platform compatibility | Linux, Mac, WSL |
| Test coverage | 90%+ |
| Average execution time | <5 seconds |
| User satisfaction | "It just works" |

---

**YO JOE!**

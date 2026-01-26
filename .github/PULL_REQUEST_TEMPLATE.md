## Description

<!-- Brief description of the changes in this PR -->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring (no functional changes)

## AI Agent Impact

<!-- How does this change affect AI agents using MAINFRAME? -->

- [ ] **Safety** - Improves validation, sandboxing, or guardrails
- [ ] **Accuracy** - Improves structured output, error handling, or first-time correctness
- [ ] **Efficiency** - Improves performance, caching, or token savings
- [ ] **New capability** - Adds functionality for agent automation
- [ ] No direct agent impact

## Which Libraries Are Affected?

<details>
<summary>Core Libraries</summary>

- [ ] common.sh (loader)
- [ ] pure-string.sh
- [ ] pure-array.sh
- [ ] pure-util.sh
- [ ] pure-file.sh
- [ ] json.sh
</details>

<details>
<summary>Agent Libraries (v3+)</summary>

- [ ] output.sh (USOP)
- [ ] agent_safety.sh
- [ ] agent_comm.sh
- [ ] idempotent.sh
- [ ] atomic.sh
- [ ] observe.sh
</details>

<details>
<summary>Other</summary>

- [ ] validation.sh
- [ ] http.sh
- [ ] datetime.sh
- [ ] csv.sh
- [ ] git.sh
- [ ] Other: ___
</details>

## Checklist

### Code Quality
- [ ] Code follows MAINFRAME style (pure bash, no external dependencies)
- [ ] Functions are documented with usage comments
- [ ] No `eval` used (or justified exception with security review)
- [ ] Function names use snake_case
- [ ] Functions are exported with `export -f`

### Testing
- [ ] All existing tests pass (`./run_tests.sh`)
- [ ] New tests added for new functionality
- [ ] ShellCheck passes with no warnings
- [ ] Tested on Bash 4.0+

### Documentation
- [ ] CHEATSHEET.md updated (if adding/changing public functions)
- [ ] CLAUDE.md updated (if AI agent behavior changes)
- [ ] README.md updated (if user-facing changes)

## Testing Instructions

```bash
# How to test this PR
source lib/common.sh
# your_function "args"

# Run specific tests
./tests/bats/bin/bats tests/your_test.bats
```

## Related Issues

<!-- Link any related issues -->
Fixes #(issue number)

## Screenshots/Examples

<!-- If applicable, show before/after or usage examples -->

```bash
# Example output
$ your_function "input"
{"ok":true,"data":"result"}
```

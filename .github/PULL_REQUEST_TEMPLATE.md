## Description

<!-- Brief description of the changes in this PR -->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring (no functional changes)

## Pi Workflow Impact

<!-- Which Pi Coding Agent workflow improves? Other coding-agent integrations are frozen compatibility scope. -->

- [ ] **Shell policy** - Improves classification or bounded execution; not OS sandboxing
- [ ] **Accuracy** - Improves structured output, error handling, or first-time correctness
- [ ] **Efficiency** - Improves performance, caching, or token savings
- [ ] **Task continuity** - Improves explicit checkpoints, recovery, or handoffs
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
<summary>Pi integration and durable runtime</summary>

- [ ] output.sh (USOP)
- [ ] agent_safety.sh
- [ ] skills/pi/extensions/mainframe.ts
- [ ] lib/durable_awm.sh
- [ ] control_plane/mainframe_control_plane
- [ ] idempotent.sh
- [ ] atomic.sh
- [ ] observe.sh
- [ ] awm.sh (Agent Working Memory)
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
- [ ] Core code uses Bash; optional host-tool dependencies are explicit
- [ ] Functions are documented with usage comments
- [ ] No `eval` used (or justified exception with security review)
- [ ] Function names use snake_case
- [ ] Public functions use the declared export policy; no new loader-order collision

### Testing
- [ ] Active Pi source checks pass (`bash scripts/test-pi-core.sh`)
- [ ] New tests added for new functionality
- [ ] ShellCheck passes with no warnings
- [ ] Tested on Bash 4.4+
- [ ] AWM state isolation verified (if touching agent libraries)
- [ ] Installed-Pi checks run when runtime behavior changes; platform and skips disclosed
- [ ] Unrelated machine packages, Pi settings, and integrations left unchanged

### Documentation
- [ ] CHEATSHEET.md updated (if adding/changing public functions)
- [ ] Pi skill and product documentation updated (if Pi behavior changes)
- [ ] README.md updated (if user-facing changes)

## Testing Instructions

```bash
# How to test this PR
source lib/common.sh
# your_function "args"

# Active Pi source checks
bash scripts/test-pi-core.sh

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

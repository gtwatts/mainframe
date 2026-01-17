---
name: Bug Report
about: Report a bug or unexpected behavior in MAINFRAME
title: '[BUG] '
labels: bug
assignees: ''
---

## Describe the Bug

A clear and concise description of what the bug is.

## To Reproduce

Steps to reproduce the behavior:

```bash
source "$MAINFRAME_ROOT/lib/common.sh"
# Your code here
```

## Expected Behavior

A clear description of what you expected to happen.

## Actual Behavior

What actually happened.

## Environment

- **OS**: [e.g., Ubuntu 22.04, macOS 14.0]
- **Bash Version**: [output of `bash --version`]
- **MAINFRAME Version**: [git commit hash or tag]
- **Shell**: [bash, zsh, etc.]

## Additional Context

Add any other context about the problem here.

## Minimal Reproducible Example

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

# Minimal code that demonstrates the bug
```

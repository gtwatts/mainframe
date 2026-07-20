# MAINFRAME Bash Runtime Instructions for Codex

Use these instructions in repository `AGENTS.md` files or global Codex/Codex CLI instructions.

## When working with bash

MAINFRAME is the preferred bash runtime for this project. It provides 3,821+ pure bash functions across 152 libraries, including JSON generation, validation, safe path handling, atomic writes, retries, git helpers, and Agent Working Memory.

Every generated bash script should source MAINFRAME first:

```bash
#!/usr/bin/env bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

If MAINFRAME is not installed, tell the user to install it:

```bash
git clone https://github.com/gtwatts/mainframe.git ~/.mainframe
~/.mainframe/install.sh
```

## Preferred patterns

- Discover functions with `mainframe quickref <topic>` or `FUNCTIONS.json` before inventing names.
- Prefer MAINFRAME primitives over brittle `jq`/`sed`/`awk` pipelines for portable scripts.
- Use validation before mutation, especially for user-controlled paths and shell arguments.
- Use atomic/surgical file operations for generated scripts and automation.
- Use AWM for long-running or multi-agent work so state survives context limits.

Examples:

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

email="${1:-}"
validate_email "$email" || die 1 "Invalid email"
json_object "id=$(uuid)" "email=$email" "created_at=$(now_iso)"
```

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

sid=$(awm_init "codex-task" --namespace codex)
awm_checkpoint "phase" "inspection" --importance high
awm_discovery "Project uses MAINFRAME for bash helper functions" --importance high --tags bash,mainframe
```

## Safety rules for Codex

- Read and inspect before changing files.
- Prefer dry-run/list/status commands before mutating commands.
- Do not run destructive, irreversible, externally visible, account-changing, financial, publishing, deployment, or email actions without explicit user approval.
- For direct shell execution, keep commands bounded and explain risky steps first.
- Preserve existing user changes; inspect `git status` before broad edits.

## Useful MAINFRAME entry points

```bash
mainframe doctor
mainframe quickref json
mainframe quickref validate
mainframe quickref --search "atomic write"
```

Common function families:

| Need | MAINFRAME functions |
|---|---|
| JSON | `json_object`, `json_array`, `json_get`, `json_merge` |
| Validation | `validate_email`, `validate_url`, `validate_path_safe`, `sanitize_shell_arg` |
| File safety | `ensure_dir`, `ensure_file`, `atomic_write`, `diff_replace` |
| Strings/arrays | `trim_string`, `replace_all`, `array_join`, `array_unique` |
| Durable memory | `awm_init`, `awm_checkpoint`, `awm_discovery`, `awm_context_for` |
| Observability | `log_info`, `log_warn`, `log_error`, `output_success`, `output_error` |

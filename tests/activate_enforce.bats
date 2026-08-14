#!/usr/bin/env bats
# Explicit host-hook enforcement activation: merge-safe, idempotent, dry-run,
# and exact-entry-only deactivation for Codex, Claude Code, Copilot, and Gemini.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-enforce-test.XXXXXX")"
    CODEX_HOOK_COMMAND="$(expected_hook_command codex)"
    CLAUDE_HOOK_COMMAND="$(expected_hook_command claude-code)"
    COPILOT_HOOK_COMMAND="$(expected_hook_command copilot)"
    GEMINI_HOOK_COMMAND="$(expected_hook_command gemini)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

mf() {
    "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" "$@"
}

expected_hook_command() {
    "$BASH_BIN" --noprofile --norc -p -c \
        'source "$1"; _mainframe_enforce_command_for "$2"' \
        _ "$PROJECT_ROOT/lib/activate.sh" "$1"
}

@test "activate --enforce: installs the official Codex PreToolUse entry" {
    run mf activate codex --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement-created"* ]]
    [ -f "$TEST_DIR/AGENTS.md" ]

    jq -e --arg command "$CODEX_HOOK_COMMAND" '
        [.hooks.PreToolUse[] | select(. == {
            matcher: "Bash",
            hooks: [{type: "command", command: $command}]
        })] | length == 1
    ' "$TEST_DIR/.codex/hooks.json" >/dev/null
}

@test "Codex activation and deactivation preserve foreign hooks and AGENTS instructions" {
    mkdir -p "$TEST_DIR/.codex"
    printf '%s\n' "Team instructions stay here." > "$TEST_DIR/AGENTS.md"
    cat > "$TEST_DIR/.codex/hooks.json" <<'JSON'
{
  "description": "team hooks",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "./team-policy.sh"}]
      }
    ]
  }
}
JSON
    before="$(jq -cS . "$TEST_DIR/.codex/hooks.json")"

    mf activate codex --project "$TEST_DIR" --enforce >/dev/null
    grep -Fq "Team instructions stay here." "$TEST_DIR/AGENTS.md"
    grep -qF "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"

    mf deactivate codex --project "$TEST_DIR" --enforce >/dev/null
    grep -Fq "Team instructions stay here." "$TEST_DIR/AGENTS.md"
    ! grep -qF "MAINFRAME:BEGIN" "$TEST_DIR/AGENTS.md"
    after="$(jq -cS . "$TEST_DIR/.codex/hooks.json")"
    [ "$after" = "$before" ]
}

@test "activate --enforce: installs the official Claude Code PreToolUse entry" {
    run mf activate claude-code --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement-created"* ]]
    [ -f "$TEST_DIR/CLAUDE.md" ]

    jq -e --arg command "$CLAUDE_HOOK_COMMAND" '
        [.hooks.PreToolUse[] | select(. == {
            matcher: "Bash",
            hooks: [{type: "command", command: $command}]
        })] | length == 1
    ' "$TEST_DIR/.claude/settings.json" >/dev/null
}

@test "activate --enforce: installs the official Gemini BeforeTool entry" {
    run mf activate gemini --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement-created"* ]]
    [ -f "$TEST_DIR/GEMINI.md" ]

    jq -e --arg command "$GEMINI_HOOK_COMMAND" '
        [.hooks.BeforeTool[] | select(. == {
            matcher: "run_shell_command",
            hooks: [{type: "command", command: $command}]
        })] | length == 1
    ' "$TEST_DIR/.gemini/settings.json" >/dev/null
}

@test "activate --enforce: installs the dedicated Copilot v1 preToolUse entry" {
    run mf activate copilot --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement-created"* ]]

    jq -e --arg command "$COPILOT_HOOK_COMMAND" '
        .version == 1 and
        ([.hooks.preToolUse[] | select(. == {
            type: "command",
            matcher: "bash",
            bash: $command
        })] | length == 1)
    ' "$TEST_DIR/.github/hooks/mainframe.json" >/dev/null
}

@test "activate --enforce: is idempotent and preserves unrelated Claude JSON" {
    mkdir -p "$TEST_DIR/.claude"
    cat > "$TEST_DIR/.claude/settings.json" <<'JSON'
{
  "permissions": {"allow": ["Read"]},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "./user-check.sh"}]
      }
    ]
  },
  "teamSetting": true
}
JSON
    before="$(jq -cS . "$TEST_DIR/.claude/settings.json")"

    mf activate claude-code --project "$TEST_DIR" --enforce >/dev/null
    run mf activate claude-code --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement-current"* ]]
    jq -e --arg command "$CLAUDE_HOOK_COMMAND" '
        [.hooks.PreToolUse[]
          | select(.matcher == "Bash")
          | .hooks[]
          | select(. == {type: "command", command: $command})
        ] | length == 1
    ' "$TEST_DIR/.claude/settings.json" >/dev/null
    jq -e '.permissions.allow == ["Read"] and .teamSetting == true' \
        "$TEST_DIR/.claude/settings.json" >/dev/null

    mf deactivate claude-code --project "$TEST_DIR" --enforce >/dev/null
    after="$(jq -cS . "$TEST_DIR/.claude/settings.json")"
    [ "$after" = "$before" ]
}

@test "deactivate --enforce: removes only exact Gemini entry" {
    mkdir -p "$TEST_DIR/.gemini"
    cat > "$TEST_DIR/.gemini/settings.json" <<'JSON'
{
  "theme": "user-theme",
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "run_shell_command",
        "hooks": [{
          "type": "command",
          "command": "mainframe agent-hook --format gemini || exit 2",
          "timeout": 2000
        }]
      }
    ]
  }
}
JSON

    mf activate gemini --project "$TEST_DIR" --enforce >/dev/null
    mf deactivate gemini --project "$TEST_DIR" --enforce >/dev/null

    jq -e '
        .theme == "user-theme" and
        (.hooks.BeforeTool | length == 1) and
        .hooks.BeforeTool[0].hooks[0].timeout == 2000
    ' "$TEST_DIR/.gemini/settings.json" >/dev/null
}

@test "deactivate --enforce: preserves unrelated Copilot hook-file data" {
    mkdir -p "$TEST_DIR/.github/hooks"
    cat > "$TEST_DIR/.github/hooks/mainframe.json" <<'JSON'
{
  "version": 1,
  "metadata": {"owner": "team"},
  "hooks": {
    "preToolUse": [
      {"type": "command", "matcher": "read", "bash": "./audit-read.sh"}
    ]
  }
}
JSON
    before="$(jq -cS . "$TEST_DIR/.github/hooks/mainframe.json")"

    mf activate copilot --project "$TEST_DIR" --enforce >/dev/null
    mf deactivate copilot --project "$TEST_DIR" --enforce >/dev/null

    after="$(jq -cS . "$TEST_DIR/.github/hooks/mainframe.json")"
    [ "$after" = "$before" ]
}

@test "deactivate --enforce: existing config without Mainframe entry is unchanged" {
    mkdir -p "$TEST_DIR/.claude"
    printf '{"permissions":{"deny":["Write"]}}\n' > "$TEST_DIR/.claude/settings.json"
    before="$(jq -cS . "$TEST_DIR/.claude/settings.json")"

    run mf deactivate claude-code --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [[ "$output" == *"no-mainframe-enforcement"* ]]

    after="$(jq -cS . "$TEST_DIR/.claude/settings.json")"
    [ "$after" = "$before" ]
}

@test "activate and deactivate --enforce: dry-run writes nothing" {
    run mf activate claude-code --project "$TEST_DIR" --enforce --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would-enforce-create"* ]]
    [ ! -e "$TEST_DIR/CLAUDE.md" ]
    [ ! -e "$TEST_DIR/.claude/settings.json" ]

    mf activate gemini --project "$TEST_DIR" --enforce >/dev/null
    before="$(jq -cS . "$TEST_DIR/.gemini/settings.json")"
    run mf deactivate gemini --project "$TEST_DIR" --enforce --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would-remove-enforcement"* ]]
    after="$(jq -cS . "$TEST_DIR/.gemini/settings.json")"
    [ "$after" = "$before" ]
    grep -q 'MAINFRAME:BEGIN' "$TEST_DIR/GEMINI.md"
}

@test "activate --enforce: invalid JSON fails before instruction activation" {
    mkdir -p "$TEST_DIR/.claude"
    printf '{not valid json\n' > "$TEST_DIR/.claude/settings.json"

    run mf activate claude-code --project "$TEST_DIR" --enforce
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid JSON object"* ]]
    [ ! -e "$TEST_DIR/CLAUDE.md" ]
    grep -qF '{not valid json' "$TEST_DIR/.claude/settings.json"
}

@test "activate --enforce: incompatible schema fails without overwriting it" {
    mkdir -p "$TEST_DIR/.gemini"
    printf '{"hooks":"keep-me"}\n' > "$TEST_DIR/.gemini/settings.json"

    run mf activate gemini --project "$TEST_DIR" --enforce
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported gemini hook schema"* ]]
    [ "$(jq -r .hooks "$TEST_DIR/.gemini/settings.json")" = "keep-me" ]
    [ ! -e "$TEST_DIR/GEMINI.md" ]
}

@test "activate --enforce: reports missing jq before writing" {
    no_jq_path="$TEST_DIR/no-jq-bin"
    mkdir -p "$no_jq_path"
    for helper in basename dirname readlink; do
        ln -s "$(command -v "$helper")" "$no_jq_path/$helper"
    done

    run env PATH="$no_jq_path" MAINFRAME_ROOT="$PROJECT_ROOT" \
        "$BASH_BIN" --noprofile --norc -p -c '
            source "$1"
            if _mainframe_enforce_bind_runtime "$2"; then
                exit 0
            fi
            printf "%s\n" "$_MAINFRAME_ENFORCE_BIND_ERROR"
            exit 1
        ' _ "$PROJECT_ROOT/lib/activate.sh" "$TEST_DIR"
    [ "$status" -ne 0 ]
    [[ "$output" == *"jq was not found"* ]]
    [ ! -e "$TEST_DIR/CLAUDE.md" ]
    [ ! -e "$TEST_DIR/.claude/settings.json" ]
}

@test "activate --enforce: rejects hosts without an enforcement adapter" {
    run mf activate cursor --project "$TEST_DIR" --enforce
    [ "$status" -ne 0 ]
    [[ "$output" == *"Enforcement is not supported for cursor"* ]]
    [ ! -e "$TEST_DIR/.cursor/rules/mainframe.mdc" ]
}

@test "activate all --enforce: configures every supported enforcement host" {
    run mf activate all --project "$TEST_DIR" --enforce
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/.codex/hooks.json" ]
    [ -f "$TEST_DIR/.claude/settings.json" ]
    [ -f "$TEST_DIR/.github/hooks/mainframe.json" ]
    [ -f "$TEST_DIR/.gemini/settings.json" ]
}

@test "activate refuses a symbolic-link instruction file without touching its target" {
    local outside="$TEST_DIR/outside-agents.md"
    printf '%s\n' 'outside sentinel' > "$outside"
    ln -s "$outside" "$TEST_DIR/AGENTS.md"

    run mf activate codex --project "$TEST_DIR" --enforce

    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing symbolic-link managed project file"* ]]
    [ "$(cat "$outside")" = "outside sentinel" ]
    [ ! -e "$TEST_DIR/.codex/hooks.json" ]
}

@test "activate refuses symbolic-link host directories before any project write" {
    local outside="$TEST_DIR/outside-claude"
    mkdir -p "$outside"
    ln -s "$outside" "$TEST_DIR/.claude"

    run mf activate claude-code --project "$TEST_DIR" --enforce

    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing symbolic-link parent"* ]]
    [ ! -e "$outside/settings.json" ]
    [ ! -e "$TEST_DIR/CLAUDE.md" ]
}

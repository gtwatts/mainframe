# AWM Cookbook

Practical workflows for Mainframe Agent Working Memory.

This cookbook follows the canonical AWM surface in [`lib/awm.sh`](/Users/gordonwatts/Documents/Projects/mainframe/lib/awm.sh). The older `awm_v2_*` names are still available as compatibility wrappers, but new agent flows should use the canonical functions below.

## 1. Start, Resume, Finish

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"

sid=$(awm_init "code-audit" --namespace security --model gpt-4o --backend file)
awm_resume "$sid"

awm_checkpoint "repo_root" "/workspace/project" --importance high
awm_checkpoint "phase" "scanning"
awm_discovery "Auth uses JWT refresh tokens" --importance critical --tags auth,jwt
awm_log "decisions" "Audit will prioritize auth and secrets" --importance high
awm_progress "scan" "12/80" "Scanning auth and config"

awm_close --export "code-audit-report.md"
```

Resume later:

```bash
if awm_resume "$sid"; then
    current_phase=$(awm_get "phase" "unknown")
    echo "Resumed at phase: $current_phase"
fi
```

## 2. Search Before Re-reading

Use `awm_find` to pull only relevant memory back into context.

```bash
results=$(awm_find "postgres auth" --kind mixed --limit 8)
echo "$results"
```

Kinds:

- `discovery`
- `checkpoint`
- `log`
- `mixed`

If semantic rerank is explicitly enabled, AWM will rerank lexical candidates using [`lib/embeddings.sh`](/Users/gordonwatts/Documents/Projects/mainframe/lib/embeddings.sh):

```bash
export MAINFRAME_AWM_FIND_EMBEDDINGS=1
results=$(awm_find "how do we rotate jwt secrets?" --kind mixed --limit 5)
```

## 3. Pack Context for a Sub-Agent

`awm_context_for` produces a deterministic context package in priority order:

1. critical discoveries
2. current progress and open state
3. relevant checkpoints
4. recent high-signal logs
5. `awm_find` matches
6. final summary

JSON form:

```bash
ctx=$(awm_context_for "dependency review" --tokens 2000)
echo "$ctx"
```

Prompt form:

```bash
prompt=$(awm_context_for "dependency review" --tokens 2000 --format prompt)
echo "$prompt"
```

Restrict included sections:

```bash
ctx=$(awm_context_for "secrets review" \
    --tokens 1500 \
    --include discoveries,progress,checkpoints)
```

## 4. Prepare and Accept Handoffs

Parent agent:

```bash
sid=$(awm_init "release-audit" --namespace release)
awm_resume "$sid"

awm_discovery "CI uses GitHub Actions and Netlify"
awm_checkpoint "open_questions" '["Do we need secret rotation?"]'
handoff=$(awm_handoff_prepare "release-reviewer" --tokens 1800)
```

Receiving agent:

```bash
new_sid=$(awm_handoff_accept "$handoff")
awm_resume "$new_sid"
awm_get "handoff_parent_session"
awm_get "handoff_context"
```

## 5. Inspect and Repair Sessions

Status:

```bash
awm_status "$sid"
```

Doctor:

```bash
awm_doctor "$sid"
```

Migrate old sessions:

```bash
awm_migrate "$sid"
awm_migrate --all
```

## 6. CLI Usage

Everything above is available from the CLI.

```bash
sid=$(mainframe awm init security-audit --namespace security)
mainframe awm checkpoint --session "$sid" phase scanning --importance high
mainframe awm discovery --session "$sid" "JWT refresh tokens enabled" --importance critical
mainframe awm find --session "$sid" jwt --kind mixed
mainframe awm handoff prepare --session "$sid" auth-reviewer --tokens 1800
mainframe awm doctor --session "$sid"
```

## 7. Choosing Between AWM and `agent_context`

Use AWM for:

- long-running agent work
- resumable tasks
- discoveries and handoffs
- retrieval and context packing
- session inspection/export

Use [`lib/agent_context.sh`](/Users/gordonwatts/Documents/Projects/mainframe/lib/agent_context.sh) when you need a generic persistent context object without the full agent-memory workflow.

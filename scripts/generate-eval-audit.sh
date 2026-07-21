#!/usr/bin/env bash
# Generate docs/SECURITY_EVAL_AUDIT.md from lib/*.sh eval call sites.
# Classification: dynamic function generation, DSL invocation, legacy traps,
# string execution. Every site gets an input-source and risk annotation.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/SECURITY_EVAL_AUDIT.md
DATE=$(date -u '+%Y-%m-%d')

classify_site() {
    local file="$1" line="$2" text="$3"
    local category="string execution" input="caller-controlled" risk="review"
    case "$text" in
        *'${fn_name}()'*|*'${func_name}()'*|*'${chained_name}()'*|*'${composed_name}()'*)
            category="dynamic function generation"; input="internal (generated name)"; risk="low-ish (name must be validated)" ;;
        *'eval "$@"'*|*'eval $cmd'*|*'eval "$cmd"'*|*'eval "$pipeline"'*|*'eval "$1"'*)
            category="string execution"; input="CALLER-CONTROLLED"; risk="HIGH if unvalidated input reaches it" ;;
        *'eval "$var_name='*|*'eval "$OPTIND"'*|*'eval "shift"'*)
            category="variable assignment"; input="internal"; risk="low" ;;
        *TRAP*|*trap*)
            category="trap management"; input="internal"; risk="low" ;;
    esac
    printf '%s|%s|%s|%s|%s' "$file" "$line" "$category" "$input" "$risk"
}

{
    printf '# Eval Usage Security Audit\n\n'
    printf '_Generated %s by scripts/generate-eval-audit.sh — do not edit by hand._\n\n' "$DATE"
    printf 'SECURITY.md states "No Eval by Default". This document is the authoritative\n'
    printf 'inventory of every `eval` call site in `lib/`, with its input source and\n'
    printf 'risk classification, so the claim stays honest and auditable.\n\n'
    printf '## Summary\n\n'
    total=$(grep -rn 'eval ' lib/*.sh | grep -vcE '^\s*#|evaluated|evaluate')
    printf -- '- **%d** call sites across **%d** libraries\n' "$total" "$(grep -rl 'eval ' lib/*.sh | wc -l | tr -d ' ')"
    printf -- '- Policy: `lib/agent_safety.sh` uses a callback whitelist (no eval) for\n'
    printf '  agent-facing execution. The sites below live in DSL/functional\n'
    printf '  composition libraries and legacy tooling.\n\n'
    printf '## Call Sites\n\n'
    printf '| File | Line | Category | Input source | Risk |\n'
    printf '|------|-----:|----------|--------------|------|\n'
    grep -rn 'eval ' lib/*.sh | grep -vE '^\s*#|evaluated|evaluate' | while IFS=: read -r file line text; do
        classify_site "$file" "$line" "$text" | awk -F'|' '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}'
    done | sort
    printf '\n## Policy\n\n'
    printf '1. **New code must not add eval call sites** without updating this audit\n'
    printf '   (CI drift check will flag it).\n'
    printf '2. CALLER-CONTROLLED string execution sites are tech debt: each needs\n'
    printf '   either an allowlist at the boundary or a migration to the callback\n'
    printf '   whitelist pattern used by `agent_safety.sh`.\n'
    printf '3. Dynamic function generation sites must validate the generated name\n'
    printf '   (alphanumeric + underscore only).\n'
} > "$OUT"

echo "Wrote $OUT ($(grep -c '^|' "$OUT") table rows)"

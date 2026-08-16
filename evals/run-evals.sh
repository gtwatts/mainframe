#!/usr/bin/env bash
# =============================================================================
# run-evals.sh - Reproducible evaluation harness (A++ Phase 3 scaffold)
#
# Emits evals/results/<UTC-timestamp>.json. Every eval reports: success_rate,
# latency, false_positives, false_negatives, environment, and limitations —
# never a single promotional percentage (per the plan's reporting rules).
#
# Currently implemented evals:
#   policy-enforcement   - destructive-command gate vs its labeled corpus
#   compaction-recovery  - AWM state recovery after a full env wipe (nonce)
#
# Documented-but-not-yet-automated (require live agent hosts):
#   parent-to-subagent handoff, cross-host handoff
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$ROOT/evals/results"
mkdir -p "$RESULTS_DIR"

BASH_BIN="${MAINFRAME_BASH:-}"
if [[ -z "$BASH_BIN" ]]; then
    for c in /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
        [[ -x "$c" ]] || continue
        v=$("$c" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 0)
        [[ "$v" -ge 4 ]] && BASH_BIN="$c" && break
    done
fi

TS=$(date -u '+%Y%m%dT%H%M%SZ')
OUT="$RESULTS_DIR/evals-$TS.json"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mainframe-evals.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --------------------------------------------------------------------------
# Eval 1: policy-enforcement — gate corpus classification accuracy
# --------------------------------------------------------------------------
eval_policy_enforcement() {
    "$BASH_BIN" -c '
        set -u
        export MAINFRAME_LIBS=all
        source "'"$ROOT"'/lib/common.sh" >/dev/null 2>&1

        # Labeled corpus (mirrors security_gate.bats §8 / export-gate-rules)
        declare -a cases=(
            "rm -rf /tmp/x|critical" "sudo rm /etc/hosts|critical"
            "mkfs.ext4 /dev/sda1|critical" "git clean -fdx|high"
            "git reset --hard HEAD~3|high" "docker system prune -a|high"
            "ls /tmp|low" "pwd|low" "echo hello|low" "git status|low"
            "cat file.txt|low" "grep foo bar|low"
        )
        total=0; correct=0; fp=0; fn=0
        for entry in "${cases[@]}"; do
            cmd="${entry%|*}"; want="${entry#*|}"
            got=$(agent_gate_classify "$cmd" 2>/dev/null | jq -r .risk 2>/dev/null || echo unknown)
            total=$((total+1))
            if [[ "$got" == "$want" ]]; then
                correct=$((correct+1))
            else
                # FP: stricter than labeled; FN: looser than labeled
                case "$want" in
                    low) [[ "$got" != "low" ]] && fp=$((fp+1)) ;;
                    critical) [[ "$got" != "critical" ]] && fn=$((fn+1)) ;;
                    high) [[ "$got" == "low" ]] && fn=$((fn+1)) || fp=$((fp+1)) ;;
                esac
            fi
        done
        printf "%d %d %d %d\n" "$total" "$correct" "$fp" "$fn"
    '
}

run_timed() {
    local start end
    start=$(python3 -c 'import time; print(time.time())')
    "$@"
    end=$(python3 -c 'import time; print(time.time())')
    python3 -c "print(int(($end-$start)*1000))"
}

echo "Running evals (this is a scaffold: results are local, reproducible)..."

p_start=$(python3 -c 'import time; print(time.time())')
read -r p_total p_correct p_fp p_fn <<< "$(eval_policy_enforcement)"
p_end=$(python3 -c 'import time; print(time.time())')
p_latency=$(python3 -c "print(int(($p_end-$p_start)*1000))")
p_rate=$(python3 -c "print(round($p_correct/$p_total, 4))")

# --------------------------------------------------------------------------
# Eval 2: compaction-recovery — AWM nonce across an env-scrubbed session
# --------------------------------------------------------------------------
c_start=$(python3 -c 'import time; print(time.time())')
c_result=$("$BASH_BIN" -c '
    set -u
    export MAINFRAME_LIBS=all AWM_ROOT="'"$TMP"'/awm"
    source "'"$ROOT"'/lib/common.sh" >/dev/null 2>&1
    awm_init "eval-compaction" >/dev/null
    nonce="nonce-$RANDOM-$$"
    awm_checkpoint nonce_key "$nonce" >/dev/null
    sid="$_AWM_SESSION_ID"
    got=$(env -i PATH="$PATH" HOME="$HOME" MAINFRAME_ROOT="'"$ROOT"'" AWM_ROOT="'"$TMP"'/awm" \
        "'"$BASH_BIN"'" -c "
            export MAINFRAME_LIBS=all
            source \"\$MAINFRAME_ROOT/lib/common.sh\" >/dev/null 2>&1
            awm_resume $sid >/dev/null 2>&1
            awm_get nonce_key")
    [[ "$got" == "$nonce" ]] && echo PASS || echo "FAIL ($got != $nonce)"
')
c_end=$(python3 -c 'import time; print(time.time())')
c_latency=$(python3 -c "print(int(($c_end-$c_start)*1000))")
[[ "$c_result" == "PASS" ]] && c_rate="1.0" || c_rate="0.0"

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
ENV_JSON=$(jq -n \
    --arg os "$(uname -s) $(uname -m)" \
    --arg bash "$($BASH_BIN -c 'echo $BASH_VERSION')" \
    --arg version "$(cat "$ROOT/VERSION")" \
    '{os: $os, bash: $bash, mainframe_version: $version, token_cost: "not-measured (no LLM in loop)", limitations: "local single-host run; corpus is small and synthetic"}')

jq -n \
    --arg ts "$TS" \
    --argjson env "$ENV_JSON" \
    --argjson p_total "$p_total" --argjson p_correct "$p_correct" \
    --argjson p_fp "$p_fp" --argjson p_fn "$p_fn" \
    --arg p_rate "$p_rate" --argjson p_latency "$p_latency" \
    --arg c_rate "$c_rate" --argjson c_latency "$c_latency" --arg c_result "$c_result" \
    '{
      generated: $ts,
      environment: $env,
      evals: [
        {
          name: "policy-enforcement",
          description: "destructive-command gate vs labeled corpus",
          success_rate: ($p_rate | tonumber),
          cases: $p_total, correct: $p_correct,
          false_positives: $p_fp, false_negatives: $p_fn,
          latency_ms: $p_latency,
          limitations: "12-case synthetic corpus; measures classification, not prevention"
        },
        {
          name: "compaction-recovery",
          description: "AWM nonce recovered from an env-scrubbed new session",
          success_rate: ($c_rate | tonumber),
          verdict: $c_result,
          false_positives: 0, false_negatives: (if $c_rate == "1.0" then 0 else 1 end),
          latency_ms: $c_latency,
          limitations: "same-host file backend; does not measure LLM context rebuild quality"
        }
      ],
      not_automated: ["parent-to-subagent handoff", "cross-host handoff (requires live hosts)"]
    }' > "$OUT"

echo "wrote $OUT"
jq '.evals[] | {name, success_rate, latency_ms}' "$OUT"

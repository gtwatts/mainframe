#!/usr/bin/env bash
# Verify that current, user-facing project documents do not drift back to
# disproven or unscoped marketing claims. Historical research is intentionally
# excluded; docs/README.md labels that material as historical.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/verify-public-claims.sh [--list-documents] [--extra-document PATH]...

Verify current MAINFRAME documentation and release-claim quarantine rules.
--list-documents prints the canonical scan/quarantine disposition and exits.
--extra-document adds a regular, non-symlink Markdown file to the same checks;
it never replaces the canonical current-document inventory.
EOF
}

# Public repository documents outside the release payload remain part of the
# claim surface. Shipped Markdown is derived below from release-payload.sh.
public_docs=(
    "$PROJECT_ROOT/CLAUDE.md"
    "$PROJECT_ROOT/CONTRIBUTING.md"
    "$PROJECT_ROOT/.github/SUPPORT.md"
    "$PROJECT_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
)
extra_docs=()
list_documents=0

while (( $# > 0 )); do
    case "$1" in
        --extra-document)
            if (( $# < 2 )); then
                printf 'ERROR: --extra-document requires a path\n' >&2
                exit 2
            fi
            if [[ ! -f "$2" || -L "$2" ]]; then
                printf 'ERROR: extra claim document must be a regular, non-symlink file: %s\n' "$2" >&2
                exit 2
            fi
            extra_docs+=("$2")
            shift 2
            ;;
        --list-documents)
            list_documents=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

failures=0

# shellcheck disable=SC1091 # Resolved from PROJECT_ROOT at runtime.
source "$PROJECT_ROOT/scripts/dev/release-payload.sh"
release_payload=""
if ! release_payload="$(mainframe_release_payload_files "$PROJECT_ROOT")"; then
    printf 'FAIL: release payload inventory could not be verified\n\n' >&2
    failures=$((failures + 1))
else
    for historical_doc in "${MAINFRAME_RELEASE_QUARANTINED_RESEARCH_DOCS[@]}"; do
        historical_path="$PROJECT_ROOT/$historical_doc"
        if [[ ! -f "$historical_path" || -L "$historical_path" ]]; then
            printf 'FAIL: quarantined historical report is missing or unsafe: %s\n\n' \
                "$historical_doc" >&2
            failures=$((failures + 1))
            continue
        fi
        if ! grep -Fq 'Historical research only' "$historical_path"; then
            printf 'FAIL: quarantined historical report lacks its evidence warning: %s\n\n' \
                "$historical_doc" >&2
            failures=$((failures + 1))
        fi
        if grep -Fxq "$historical_doc" <<<"$release_payload"; then
            printf 'FAIL: quarantined historical report entered the release payload: %s\n\n' \
                "$historical_doc" >&2
            failures=$((failures + 1))
        fi
    done
fi

declare -A historical_markdown=()
declare -A shipped_markdown=()
quarantined_docs=()

for historical_doc in "${MAINFRAME_RELEASE_QUARANTINED_HISTORICAL_MARKDOWN[@]}"; do
    if [[ "$historical_doc" != *.md ]]; then
        printf 'FAIL: historical Markdown quarantine is not Markdown: %s\n\n' \
            "$historical_doc" >&2
        failures=$((failures + 1))
        continue
    fi
    if [[ -n "${historical_markdown[$historical_doc]:-}" ]]; then
        printf 'FAIL: duplicate historical Markdown quarantine: %s\n\n' \
            "$historical_doc" >&2
        failures=$((failures + 1))
        continue
    fi
    historical_markdown["$historical_doc"]=1
done

if [[ -n "$release_payload" ]]; then
    while IFS= read -r relative_path; do
        [[ "$relative_path" == *.md ]] || continue
        if [[ -n "${shipped_markdown[$relative_path]:-}" ]]; then
            printf 'FAIL: duplicate Markdown path in release payload: %s\n\n' \
                "$relative_path" >&2
            failures=$((failures + 1))
            continue
        fi
        shipped_markdown["$relative_path"]=1
        if [[ -n "${historical_markdown[$relative_path]:-}" ]]; then
            quarantined_docs+=("$relative_path")
        else
            public_docs+=("$PROJECT_ROOT/$relative_path")
        fi
    done <<< "$release_payload"
fi

for historical_doc in "${!historical_markdown[@]}"; do
    if [[ -z "${shipped_markdown[$historical_doc]:-}" ]]; then
        printf 'FAIL: historical Markdown quarantine is not in the release payload: %s\n\n' \
            "$historical_doc" >&2
        failures=$((failures + 1))
    fi
done

for public_doc in "${public_docs[@]}"; do
    if [[ ! -f "$public_doc" || -L "$public_doc" ]]; then
        printf 'FAIL: current claim document is missing or unsafe: %s\n\n' \
            "$public_doc" >&2
        failures=$((failures + 1))
    fi
done

public_docs+=("${extra_docs[@]}")

if (( list_documents )); then
    for public_doc in "${public_docs[@]}"; do
        if [[ "$public_doc" == "$PROJECT_ROOT/"* ]]; then
            printf 'scan\t%s\n' "${public_doc#"$PROJECT_ROOT/"}"
        else
            printf 'scan-extra\t%s\n' "$public_doc"
        fi
    done
    for historical_doc in "${quarantined_docs[@]}"; do
        printf 'quarantine\t%s\n' "$historical_doc"
    done
    (( failures == 0 )) || exit 1
    exit 0
fi

reject() {
    local description="$1"
    local pattern="$2"
    local matches

    matches=$(grep -nEi "$pattern" "${public_docs[@]}" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        printf 'FAIL: %s\n%s\n\n' "$description" "$matches" >&2
        failures=$((failures + 1))
    fi
}

format_count() {
    local value="$1" rendered='' group
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    while (( value >= 1000 )); do
        printf -v group '%03d' "$((value % 1000))"
        rendered=",$group$rendered"
        value=$((value / 1000))
    done
    printf '%d%s\n' "$value" "$rendered"
}

require_literal() {
    local description="$1" literal="$2" document="$3"
    if ! grep -Fq "$literal" "$document"; then
        printf 'FAIL: %s\nexpected: %s\ndocument: %s\n\n' \
            "$description" "$literal" "${document#"$PROJECT_ROOT/"}" >&2
        failures=$((failures + 1))
    fi
}

verify_generated_count_claims() {
    local unique registrations libraries stable python_bin='' mcp_counts
    local unique_f registrations_f libraries_f stable_f extra matches

    if ! command -v jq >/dev/null 2>&1; then
        printf 'FAIL: jq is required to verify generated registry claims\n\n' >&2
        failures=$((failures + 1))
        return
    fi
    unique="$(jq -er '.stats.unique_functions | select(type == "number")' \
        "$PROJECT_ROOT/FUNCTIONS.json" 2>/dev/null)" || unique=''
    registrations="$(jq -er '.stats.registrations | select(type == "number")' \
        "$PROJECT_ROOT/FUNCTIONS.json" 2>/dev/null)" || registrations=''
    libraries="$(jq -er '.stats.total_libraries | select(type == "number")' \
        "$PROJECT_ROOT/FUNCTIONS.json" 2>/dev/null)" || libraries=''
    if [[ ! "$unique" =~ ^[0-9]+$ || ! "$registrations" =~ ^[0-9]+$ ||
          ! "$libraries" =~ ^[0-9]+$ ]]; then
        printf 'FAIL: generated registry statistics are missing or malformed\n\n' >&2
        failures=$((failures + 1))
        return
    fi

    for candidate in \
        "${MAINFRAME_PYTHON:-}" \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3 \
        /usr/bin/python3; do
        [[ -n "$candidate" && "$candidate" == /* && -x "$candidate" ]] || continue
        python_bin="$candidate"
        break
    done
    if [[ -z "$python_bin" ]]; then
        printf 'FAIL: Python 3 is required to verify generated MCP claims\n\n' >&2
        failures=$((failures + 1))
        return
    fi
    mcp_counts="$("$python_bin" -I -S -B - "$PROJECT_ROOT" <<'PY'
import os
import sys

root = os.path.realpath(sys.argv[1])
sys.path.insert(0, os.path.join(root, "mcp", "src"))
from mainframe_mcp.tool_registry import ToolRegistry

registry = ToolRegistry(mainframe_root=root)
if not registry.load():
    raise SystemExit("registry failed to load")
print(len(registry.generate_all_tools(tier="stable-core")))
PY
)" || mcp_counts=''
    stable="$mcp_counts"
    if [[ ! "$stable" =~ ^[0-9]+$ ]]; then
        printf 'FAIL: generated MCP stable-core count is missing or malformed\n\n' >&2
        failures=$((failures + 1))
        return
    fi

    unique_f="$(format_count "$unique")"
    registrations_f="$(format_count "$registrations")"
    libraries_f="$(format_count "$libraries")"
    stable_f="$(format_count "$stable")"

    require_literal 'MCP README stable-core count drifted from generated policy' \
        "the $stable_f reviewed \`stable-core\` tools" "$PROJECT_ROOT/mcp/README.md"
    require_literal 'integration matrix function count drifted from FUNCTIONS.json' \
        "$unique_f unique functions" "$PROJECT_ROOT/docs/INTEGRATION_MATRIX.md"
    require_literal 'integration matrix registration count drifted from FUNCTIONS.json' \
        "$registrations_f registrations" "$PROJECT_ROOT/docs/INTEGRATION_MATRIX.md"
    require_literal 'integration matrix library count drifted from FUNCTIONS.json' \
        "$libraries_f libraries" "$PROJECT_ROOT/docs/INTEGRATION_MATRIX.md"
    require_literal 'compatibility LSP function count drifted from FUNCTIONS.json' \
        "$unique_f owner-filtered candidate entries" "$PROJECT_ROOT/docs/COMPATIBILITY.md"
    require_literal 'compatibility MCP count drifted from generated policy' \
        "Exactly $stable_f brokered stable-core tools" "$PROJECT_ROOT/docs/COMPATIBILITY.md"
    require_literal 'canonical manifest registration count drifted from MANIFEST.json' \
        "$registrations_f registrations" "$PROJECT_ROOT/docs/CANONICAL_MANIFEST.md"
    require_literal 'canonical manifest export count drifted from MANIFEST.json' \
        "$unique_f unique names" "$PROJECT_ROOT/docs/CANONICAL_MANIFEST.md"

    for extra in "${extra_docs[@]}"; do
        matches="$(grep -nEi '[0-9][0-9,]*[[:space:]]+Registry Functions' "$extra" 2>/dev/null |
            grep -Fvi "$unique_f Registry Functions" || true)"
        if [[ -n "$matches" ]]; then
            printf 'FAIL: Generated registry count claims are stale\n%s\n\n' "$matches" >&2
            failures=$((failures + 1))
        fi
        matches="$(grep -nEi '[0-9][0-9,]*[[:space:]]+(reviewed[[:space:]]+)?(stable-core[[:space:]]+)?(MCP[[:space:]]+)?tools' "$extra" 2>/dev/null |
            grep -Fvi "$stable_f" || true)"
        if [[ -n "$matches" ]]; then
            printf 'FAIL: Generated MCP stable-core claims are stale\n%s\n\n' "$matches" >&2
            failures=$((failures + 1))
        fi
    done

    printf 'Generated registry claim parity passed: %s exports, %s registrations, %s libraries, %s public MCP tools.\n' \
        "$unique_f" "$registrations_f" "$libraries_f" "$stable_f"
}

verify_generated_gate_claims() {
    local python_bin='' candidate gate_claim_output

    for candidate in \
        "${MAINFRAME_PYTHON:-}" \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3 \
        /usr/bin/python3; do
        [[ -n "$candidate" && "$candidate" == /* && -x "$candidate" ]] || continue
        python_bin="$candidate"
        break
    done
    if [[ -z "$python_bin" ]]; then
        printf 'FAIL: Python 3 is required to verify generated gate claims\n\n' >&2
        failures=$((failures + 1))
        return
    fi

    if ! gate_claim_output="$("$python_bin" -I -S -B - \
        "$PROJECT_ROOT" "${#extra_docs[@]}" "${public_docs[@]}" 2>&1 <<'PY'
import ast
import json
import os
import re
import sys
from pathlib import Path


def metadata_failure(message):
    print("FAIL: Generated gate claim metadata is malformed", file=sys.stderr)
    print(message, file=sys.stderr)
    print(file=sys.stderr)
    raise SystemExit(1)


root = Path(os.path.realpath(sys.argv[1]))
try:
    extra_count = int(sys.argv[2])
except ValueError:
    metadata_failure("extra-document count is not an integer")
documents = [Path(path) for path in sys.argv[3:]]
if extra_count < 0 or extra_count > len(documents):
    metadata_failure("extra-document count is outside the document inventory")
extra_documents = set(documents[-extra_count:]) if extra_count else set()

try:
    gate_payload = json.loads((root / "security/gate-rules.json").read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    metadata_failure(f"security/gate-rules.json could not be read: {exc}")
rules = gate_payload.get("rules")
if not isinstance(rules, list) or not rules:
    metadata_failure("security/gate-rules.json must contain a nonempty rules array")
rule_count = len(rules)

exporter = root / "scripts/export-gate-rules.py"
try:
    exporter_tree = ast.parse(exporter.read_text(encoding="utf-8"), filename=str(exporter))
except (OSError, UnicodeError, SyntaxError) as exc:
    metadata_failure(f"gate exporter could not be parsed: {exc}")
corpus_values = []
for node in exporter_tree.body:
    if not isinstance(node, ast.Assign):
        continue
    if any(isinstance(target, ast.Name) and target.id == "CORPUS" for target in node.targets):
        corpus_values.append(node.value)
if len(corpus_values) != 1:
    metadata_failure("gate exporter must contain exactly one literal CORPUS assignment")
try:
    corpus = ast.literal_eval(corpus_values[0])
except (ValueError, TypeError, SyntaxError) as exc:
    metadata_failure(f"gate exporter CORPUS is not literal data: {exc}")
if not isinstance(corpus, list) or not corpus:
    metadata_failure("gate exporter CORPUS must be a nonempty list")
if any(
    not isinstance(case, (tuple, list))
    or len(case) != 2
    or not all(isinstance(value, str) for value in case)
    for case in corpus
):
    metadata_failure("every gate exporter CORPUS case must contain two strings")
corpus_count = len(corpus)

count = r"(?P<count>[0-9][0-9,]*)"
rule_patterns = [
    re.compile(count + r"\s+canonical(?:\s+lexical\s+gate)?\s+rules?", re.I),
    re.compile(count + r"\s+source\s+rules?", re.I),
    re.compile(count + r"\s+ordered\s+(?:rules?|patterns?)", re.I),
    re.compile(r"ordered\s+" + count + r"\s*-\s*rule\s+lexical\s+policy", re.I),
    re.compile(r"across\s+all\s+" + count + r"\s+rules?", re.I),
]
corpus_patterns = [
    re.compile(count + r"\s+corpus\s+cases?", re.I),
    re.compile(count + r"\s+Bash\s*/\s*JavaScript\s+(?:parity\s+)?cases?", re.I),
    re.compile(count + r"\s*-\s*case\s+corpus", re.I),
    re.compile(count + r"\s+cases?\s+across\s+all\s+[0-9][0-9,]*\s+rules?", re.I),
]
historical_header = re.compile(
    r"^>\s+\*\*Historical v[0-9]+\.[0-9]+\.[0-9]+ verification record\.\*\*",
    re.M,
)
problems = {"rules": [], "corpus": []}

for document in documents:
    try:
        text = document.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        metadata_failure(f"claim document could not be read ({document}): {exc}")
    if document not in extra_documents and historical_header.search(text):
        continue
    for kind, expected, patterns in (
        ("rules", rule_count, rule_patterns),
        ("corpus", corpus_count, corpus_patterns),
    ):
        seen = set()
        for pattern in patterns:
            for match in pattern.finditer(text):
                key = (match.start(), match.end(), match.group("count"))
                if key in seen:
                    continue
                seen.add(key)
                actual = int(match.group("count").replace(",", ""))
                if actual == expected:
                    continue
                line = text.count("\n", 0, match.start()) + 1
                excerpt = " ".join(match.group(0).split())
                problems[kind].append(
                    f"{document}:{line}: found {actual}, expected {expected}: {excerpt}"
                )

if problems["rules"]:
    print("FAIL: Generated gate-rule count claims are stale", file=sys.stderr)
    print("\n".join(problems["rules"]), file=sys.stderr)
    print(file=sys.stderr)
if problems["corpus"]:
    print("FAIL: Generated exporter corpus claims are stale", file=sys.stderr)
    print("\n".join(problems["corpus"]), file=sys.stderr)
    print(file=sys.stderr)
if problems["rules"] or problems["corpus"]:
    raise SystemExit(1)

print(f"{rule_count}\t{corpus_count}")
PY
    )"; then
        printf '%s\n' "$gate_claim_output" >&2
        failures=$((failures + 1))
        return
    fi

    printf 'Generated gate claim parity passed: %s rules, %s corpus cases.\n' \
        "${gate_claim_output%%$'\t'*}" "${gate_claim_output#*$'\t'}"
}

verify_generated_count_claims
verify_generated_gate_claims

verify_control_plane_claim() {
    local python_bin='' claim_json advertised
    local candidate

    for candidate in \
        "${MAINFRAME_PYTHON:-}" \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /home/linuxbrew/.linuxbrew/bin/python3 \
        /usr/bin/python3; do
        [[ -n "$candidate" && "$candidate" == /* && -x "$candidate" ]] || continue
        python_bin="$candidate"
        break
    done
    if [[ -z "$python_bin" ]]; then
        printf 'FAIL: Python 3 is required to verify the control-plane claim contract\n\n' >&2
        failures=$((failures + 1))
        return
    fi
    if ! claim_json="$("$python_bin" -I -S -B \
        "$PROJECT_ROOT/scripts/check-control-plane-claim.py" \
        --root "$PROJECT_ROOT" --json)"; then
        printf 'FAIL: control-plane claim contract is invalid\n%s\n\n' \
            "$claim_json" >&2
        failures=$((failures + 1))
        return
    fi
    advertised="$("$python_bin" -I -S -B - "$claim_json" <<'PY'
import json
import sys

print(json.loads(sys.argv[1])["advertised_claim"])
PY
)" || advertised=''
    if [[ -z "$advertised" ]]; then
        printf 'FAIL: control-plane advertised claim could not be read\n\n' >&2
        failures=$((failures + 1))
        return
    fi
    CONTROL_PLANE_ADVERTISED_CLAIM="$advertised"
    printf 'Control-plane claim contract passed: advertised=%s.\n' "$advertised"
}

CONTROL_PLANE_ADVERTISED_CLAIM=''
verify_control_plane_claim

reject "Bash 4.0 is below the supported runtime" 'bash[[:space:]]+4\.0\+'
reject "Do not describe the whole product as dependency-free" '(^|[^[:alnum:]])zero dependencies([^[:alnum:]]|$)'
reject "Do not describe the whole product as externally dependency-free" 'zero external dependencies'
reject "Known stale function counts must not appear in current guidance" '(3,?821|4,?000|4,?230|4,?458)\+?[[:space:]]+(pure[[:space:]]+bash[[:space:]]+|bash[[:space:]]+)?functions'
reject "MAINFRAME has reviewed eval sites; do not claim otherwise" 'mainframe never uses.*eval'
reject "Static test totals drift; cite the suite or generated evidence" '6,?500\+[[:space:]]+tests|11,?300\+[[:space:]]+tests|11,?360[[:space:]]+tests'
reject "Token-saving percentages require a published evaluation" '(token[[:space:]]+(savings|consumption|reduction)|context([[:space:]]+window)?[[:space:]]+(savings|reduction)).*[0-9]+%|[0-9]+%.*(token[[:space:]]+(savings|consumption|reduction)|context([[:space:]]+window)?[[:space:]]+(savings|reduction))'
reject "Agent success percentages require a published evaluation" 'first[- ](run|time)([[:space:]]+correctness)?([[:space:]]+success([[:space:]]+rate)?)?.*[0-9]+%|[0-9]+%.*first[- ](run|time)([[:space:]]+correctness)?([[:space:]]+success([[:space:]]+rate)?)?|(^|[^0-9])~?99%([^0-9]|$)'
reject "Sample-size claims require published raw evaluation evidence" 'based on[[:space:]]+[0-9,]+[[:space:]]+(bash[[:space:]]+)?task samples'
reject "Productivity claims require a live comparative evaluation" '3x more productivity|3x more effective context capacity|real-world impact:[[:space:]]*ai assistant productivity|reduces token usage by[[:space:]]+[0-9]+%'
reject "Unbounded autonomy claims exceed the AWM evidence boundary" 'unlimited state|truly autonomous'
reject "Universal speedup ranges require a published benchmark" '20[[:space:]]*-[[:space:]]*72x([[:space:]]+faster|[[:space:]]+speedup)?'
reject "Verification and recovery targets are not shipped guarantees" 'catch 90%|recover from 70%'
reject "The public MCP runner no longer supports legacy tier selection" 'MAINFRAME_MCP_TIER[[:space:]]*=[[:space:]]*(core|full)|explicit MCP [`'"'"']?(core|full)|MCP [`'"'"']?(core|full)[`'"'"']? tier'
reject "The language bindings are not published registry packages" '(pip|npm)[[:space:]]+install[[:space:]]+mainframe-bash'
if [[ "$CONTROL_PLANE_ADVERTISED_CLAIM" != category-claim ]]; then
    reject "Ultimate control-plane language requires the category-claim gate" 'MAINFRAME[[:space:]]+(is|has[[:space:]]+become)[[:space:]]+(the[[:space:]]+)?ultimate|ultimate[[:space:]]+AI([[:space:]-]+coding)?[[:space:]-]+agent[[:space:]]+control[[:space:]-]+plane'
fi

if (( failures > 0 )); then
    printf 'Public claim verification failed with %d rule(s).\n' "$failures" >&2
    exit 1
fi

printf 'Public claim verification passed for %d current documents.\n' "${#public_docs[@]}"

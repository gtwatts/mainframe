#!/usr/bin/env bash
# Shared release payload inventory for archives, checksums, and the SBOM.
# This file is sourced by release tooling; it does not perform work itself.

MAINFRAME_RELEASE_PAYLOAD_ROOTS=(
    VERSION
    package.json
    FUNCTIONS.json
    FUNCTIONS.lsp.json
    MANIFEST.json
    INVOCATION_INDEX.json
    sbom.json
    mainframe
    control_plane
    bin
    lib
    config
    security/gate-rules.json
    security/gate-normalizer.mjs
    evals/agent-impact
    skills
    scripts
    completions
    hooks
    packaging
    install.sh
    uninstall.sh
    get-mainframe.sh
    CHEATSHEET.md
    README.md
    INSTALL.md
    SECURITY.md
    CHANGELOG.md
    docs
    LICENSE
)

# Git provenance uses these pathspecs to describe the same payload surface as
# mainframe_release_payload_files. They are internal release inputs: callers
# must never copy the paths themselves into a public candidate manifest.
MAINFRAME_RELEASE_PAYLOAD_EXCLUDED_TREES=(
    docs/research
    evals/agent-impact/private
    evals/agent-impact/runs
)

MAINFRAME_RELEASE_PAYLOAD_EXCLUDED_FILES=(
    docs/MAINFRAME_Technical_Report.md
    docs/VALUE_PROOF.md
    # MCP is distributed only through the separately built, runtime-bound
    # Python package. Keep the retired shell server out if it is reintroduced.
    lib/mcp_server.sh
    skills/claude-code/mcp-server.sh
    # macOS/iCloud conflict copies are not authoritative generators. This
    # exact stale alternate existed in the source tree and must never be
    # signed or shipped alongside the canonical contract-bound generator.
    "scripts/generate-host-adapters 2.sh"
    "config/invocation-policy 2.json"
)

# Mutable claim receipts and their reference-bearing contract are detached
# attestations over the release subject. They remain package metadata, but
# including them in that subject would create a digest cycle:
# inventory -> receipt -> contract receipt_ref -> inventory.
MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS_FILE="config/release-attestation-exclusions.txt"
MAINFRAME_RELEASE_EXPECTED_ATTESTATION_EXCLUSIONS=(
    SHA256SUMS
    config/control-plane-claim.json
    config/control-plane-claim-receipts/
)
MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS=()

mainframe_release_load_attestation_exclusions() {
    local root="${1:?release root is required}"
    local registry="$root/$MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS_FILE"
    local line index
    local -a loaded=()

    if [[ ! -f "$registry" || -L "$registry" ]]; then
        printf 'release attestation exclusion registry is missing or unsafe: %s\n' \
            "$MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS_FILE" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        loaded+=("$line")
    done < "$registry"
    if (( ${#loaded[@]} != ${#MAINFRAME_RELEASE_EXPECTED_ATTESTATION_EXCLUSIONS[@]} )); then
        printf 'release attestation exclusion registry has unexpected entries\n' >&2
        return 1
    fi
    for ((index = 0; index < ${#loaded[@]}; index++)); do
        if [[ "${loaded[index]}" != \
              "${MAINFRAME_RELEASE_EXPECTED_ATTESTATION_EXCLUSIONS[index]}" ]]; then
            printf 'release attestation exclusion registry has unexpected entries\n' >&2
            return 1
        fi
    done
    MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS=("${loaded[@]}")
}

mainframe_release_path_is_attestation_metadata() {
    local relative="${1:?release path is required}"
    local excluded

    for excluded in "${MAINFRAME_RELEASE_ATTESTATION_EXCLUSIONS[@]}"; do
        if [[ "$excluded" == */ ]]; then
            [[ "$relative" == "$excluded"* ]] && return 0
        elif [[ "$relative" == "$excluded" ]]; then
            return 0
        fi
    done
    return 1
}

# These repository-only reports preserve historical research, but their
# productivity, token, benchmark, and agent-outcome figures were never promoted
# to current evidence under docs/CLAIMS_AND_BENCHMARKS.md. Keep them available
# to maintainers without shipping them as release documentation.
# shellcheck disable=SC2034 # Consumed by scripts/verify-public-claims.sh.
MAINFRAME_RELEASE_QUARANTINED_RESEARCH_DOCS=(
    docs/MAINFRAME_Technical_Report.md
    docs/VALUE_PROOF.md
)

# Historical Markdown that remains in release archives for project context.
# Public-claim verification must account for every shipped Markdown file and
# may skip only these exact paths. Additions are scanned by default until they
# are deliberately classified here.
# shellcheck disable=SC2034 # Consumed by scripts/verify-public-claims.sh.
MAINFRAME_RELEASE_QUARANTINED_HISTORICAL_MARKDOWN=(
    docs/AGENTIC_TRANSFORMATION_COMPLETE.md
    docs/AI_NATIVE_BASH_VISION_V10.md
    docs/AMMA_V3_SUMMARY.md
    docs/COMPREHENSIVE_REVIEW_REPORT.md
    docs/MEMORY_ARCHITECTURE_V3.md
    docs/PARADIGMS.md
    docs/PROJECT_REVIEW_2026-05-18.md
    docs/ROADMAP_10_PHASE.md
    docs/V10_ENGINEERING_PLAN.md
    docs/V10_SUMMARY.md
    docs/VERIFICATION_REPORT.md
    docs/VIBECODER_RESEARCH_REPORT.md
    docs/analysis/AGENT_INTEGRATION_SUMMARY.md
    docs/analysis/AGENT_INTEROPERABILITY_ANALYSIS.md
    docs/analysis/KIMI_PROFESSIONAL_PROPOSAL.md
    docs/analysis/KIMI_PROFESSIONAL_V2_HYBRID.md
    docs/analysis/KIMI_PROFESSIONAL_V3_FINAL.md
    docs/analysis/KIMI_PROFESSIONAL_V4_ULTIMATE.md
    docs/analysis/PERFORMANCE_SWEEP_REPORT.md
    docs/analysis/SECURITY_AUDIT.md
    docs/analysis/USOP_V3_IMPLEMENTATION.md
    docs/designs/AWM_MCP_BRIDGE_DESIGN.md
    docs/designs/AWM_V2_ARCHITECTURE.md
    docs/designs/EXPANSION_MASTER_PLAN.md
    docs/designs/MAINFRAME_RESEARCH_IDEATION_SUMMARY.md
    docs/designs/MAINFRAME_ROADMAP_2026.md
    docs/designs/SECURITY_HARDENING.md
    docs/designs/v6.0-SECURITY-REVIEW.md
    docs/reviews/ARCHITECTURE_REVIEW.md
    docs/reviews/COUNCIL_FRAMEWORK.md
    docs/reviews/ENGINEERING_REVIEW.md
    docs/reviews/PARADIGM_DESIGN_REVIEW.md
)

mainframe_release_payload_git_pathspecs() {
    local path

    for path in "${MAINFRAME_RELEASE_PAYLOAD_ROOTS[@]}"; do
        printf ':(top,literal)%s\0' "$path"
    done
    for path in "${MAINFRAME_RELEASE_PAYLOAD_EXCLUDED_TREES[@]}"; do
        printf ':(top,exclude,literal)%s\0' "$path"
    done
    for path in "${MAINFRAME_RELEASE_PAYLOAD_EXCLUDED_FILES[@]}"; do
        printf ':(top,exclude,literal)%s\0' "$path"
    done
    printf '%s\0' \
        ':(top,glob,exclude)**/node_modules/**' \
        ':(top,glob,exclude)**/__pycache__/**' \
        ':(top,glob,exclude)**/*.py[co]'
}

mainframe_release_payload_files() {
    local root="${1:?release root is required}"
    local path required_runtime

    mainframe_release_load_attestation_exclusions "$root" || return 1

    for path in "${MAINFRAME_RELEASE_PAYLOAD_ROOTS[@]}"; do
        if [[ ! -e "$root/$path" ]]; then
            printf 'required release payload is missing: %s\n' "$path" >&2
            return 1
        fi
    done

    for required_runtime in \
        bin/mainframe \
        control_plane/mainframe-control-plane \
        install.sh \
        scripts/upgrade-release.sh
    do
        if [[ ! -f "$root/$required_runtime" || ! -x "$root/$required_runtime" ]]; then
            printf 'required release executable is missing or non-executable: %s\n' \
                "$required_runtime" >&2
            return 1
        fi
    done

    if find "${MAINFRAME_RELEASE_PAYLOAD_ROOTS[@]/#/$root/}" \
        -path "$root/docs/MAINFRAME_Technical_Report.md" -prune -o \
        -path "$root/docs/VALUE_PROOF.md" -prune -o \
        -path "$root/lib/mcp_server.sh" -prune -o \
        -path "$root/skills/claude-code/mcp-server.sh" -prune -o \
        -path "$root/scripts/generate-host-adapters 2.sh" -prune -o \
        -path "$root/config/invocation-policy 2.json" -prune -o \
        -path "$root/evals/agent-impact/private" -prune -o \
        -path "$root/evals/agent-impact/runs" -prune -o \
        -path '*/node_modules' -prune -o \
        -path '*/__pycache__' -prune -o \
        -type l -print -quit \
        | grep -q .; then
        printf 'release payload must not contain symbolic links\n' >&2
        return 1
    fi

    (
        cd "$root" || return 1
        find "${MAINFRAME_RELEASE_PAYLOAD_ROOTS[@]}" \
            -path 'docs/research' -prune -o \
            -path 'docs/MAINFRAME_Technical_Report.md' -prune -o \
            -path 'docs/VALUE_PROOF.md' -prune -o \
            -path 'lib/mcp_server.sh' -prune -o \
            -path 'skills/claude-code/mcp-server.sh' -prune -o \
            -path 'scripts/generate-host-adapters 2.sh' -prune -o \
            -path 'config/invocation-policy 2.json' -prune -o \
            -path 'evals/agent-impact/private' -prune -o \
            -path 'evals/agent-impact/runs' -prune -o \
            -path '*/node_modules' -prune -o \
            -path '*/__pycache__' -prune -o \
            -name '*.py[co]' -prune -o \
            -type f -print \
            | LC_ALL=C sort
    )
}

mainframe_release_subject_files() {
    local root="${1:?release root is required}"
    local inventory path

    inventory=$(mktemp "${TMPDIR:-/tmp}/mainframe-release-subject.XXXXXX") || \
        return 1
    if ! mainframe_release_payload_files "$root" > "$inventory"; then
        rm -f "$inventory"
        return 1
    fi
    while IFS= read -r path; do
        mainframe_release_path_is_attestation_metadata "$path" || \
            printf '%s\n' "$path"
    done < "$inventory"
    rm -f "$inventory"
}

#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/release_readiness.sh - Offline release-readiness summary
# =============================================================================
# This report deliberately reads only files shipped in the current MAINFRAME
# tree. It does not contact GitHub, execute a release candidate, or infer that a
# workflow definition ran successfully. External CI, publication, and Homebrew
# availability therefore remain unverified until an operator checks them.
# =============================================================================

[[ -n "${_MAINFRAME_RELEASE_READINESS_LOADED:-}" ]] && return 0
declare -g _MAINFRAME_RELEASE_READINESS_LOADED=1

_mainframe_release_readiness_usage() {
    cat <<'EOF'
Usage: mainframe release readiness [--json]

Inspect the checked-in release and Pi compatibility contracts without network
access or mutation. A workflow definition is never treated as a successful CI
run, and this offline command never claims that a GitHub release or Homebrew tap
is public.

Exit 0 means every checked-in and external requirement is proven (not currently
possible in offline mode); exit 2 means inspection succeeded but release
readiness is not proven; exit 1 means the local contracts could not be trusted.
EOF
}

_mainframe_release_readiness_error() {
    local json="$1" message="$2" jq_bin="${_MAINFRAME_CLI_JQ:-}"

    if [[ "$json" == true && "$jq_bin" == /* && -x "$jq_bin" ]]; then
        "$jq_bin" -cn --arg message "$message" '
          {
            schema_version: 1,
            kind: "mainframe-release-readiness",
            scope: "offline-checked-in-evidence-only",
            overall: {
              ready: false,
              status: "INSPECTION_BLOCKED",
              message: $message
            }
          }
        '
    else
        printf 'MAINFRAME release readiness: %s\n' "$message" >&2
    fi
    # Callers choose the public exit code (usage=2, inspection=1). Returning
    # success here keeps the CLI's `set -e` from bypassing that explicit code.
    return 0
}

_mainframe_release_readiness() {
    local json=false version='' jq_bin="${_MAINFRAME_CLI_JQ:-}"
    local platforms_file compatibility_file workflow_file workflow_state required
    local advertised_json certified_json missing_json unexpected_json
    local certifications_json report
    local -a required_files=()

    while (( $# > 0 )); do
        case "$1" in
            --json)
                [[ "$json" == false ]] || {
                    _mainframe_release_readiness_error false '--json may be passed only once'
                    return 2
                }
                json=true
                shift
                ;;
            -h|--help)
                _mainframe_release_readiness_usage
                return 0
                ;;
            *)
                _mainframe_release_readiness_error false "unknown option: $1"
                _mainframe_release_readiness_usage >&2
                return 2
                ;;
        esac
    done

    [[ "$jq_bin" == /* && -f "$jq_bin" && ! -L "$jq_bin" && -x "$jq_bin" ]] || {
        _mainframe_release_readiness_error "$json" 'trusted jq is unavailable'
        return 1
    }

    platforms_file="$MAINFRAME_ROOT/scripts/dev/native-host/release-platforms.json"
    compatibility_file="$MAINFRAME_ROOT/config/pi-compatibility.json"
    workflow_file="$MAINFRAME_ROOT/.github/workflows/test.yml"
    required_files=(
        "$MAINFRAME_ROOT/VERSION"
        "$platforms_file"
        "$compatibility_file"
        "$MAINFRAME_ROOT/scripts/dev/release-candidate.sh"
        "$MAINFRAME_ROOT/packaging/homebrew/Formula/mainframe.rb.in"
        "$MAINFRAME_ROOT/get-mainframe.sh"
    )
    for required in "${required_files[@]}"; do
        if [[ ! -f "$required" || -L "$required" || ! -r "$required" ]]; then
            _mainframe_release_readiness_error "$json" \
                "required checked-in contract is missing or unsafe: ${required#"$MAINFRAME_ROOT"/}"
            return 1
        fi
    done

    # The workflow is intentionally repository-only and is not part of the
    # installed runtime archive. Presence proves only that source has a
    # definition; absence in an installed tree is expected and proves nothing
    # about CI execution. A present-but-unsafe path is still an inspection error.
    workflow_state='not-shipped-not-execution-proof'
    if [[ -e "$workflow_file" || -L "$workflow_file" ]]; then
        if [[ ! -f "$workflow_file" || -L "$workflow_file" || ! -r "$workflow_file" ]]; then
            _mainframe_release_readiness_error "$json" \
                'repository workflow definition is present but unsafe'
            return 1
        fi
        workflow_state='present-not-execution-proof'
    fi

    IFS= read -r version < "$MAINFRAME_ROOT/VERSION" || true
    if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        _mainframe_release_readiness_error "$json" 'VERSION is not stable SemVer'
        return 1
    fi

    if ! "$jq_bin" -e '
      .schema_version == 1 and
      (.platforms | type == "array" and length > 0) and
      ([.platforms[].id] | length == (unique | length)) and
      all(.platforms[];
        (.id | type == "string" and length > 0) and
        (.os | type == "string" and length > 0) and
        (.arch | type == "string" and length > 0) and
        (.system_libc | type == "string" and length > 0)
      )
    ' "$platforms_file" >/dev/null 2>&1; then
        _mainframe_release_readiness_error "$json" \
            'advertised platform contract is malformed'
        return 1
    fi

    if ! "$jq_bin" -e --arg version "$version" '
      .schema_version == 1 and
      .integration == "@gtwatts/mainframe-pi" and
      .mainframe_version == $version and
      .unknown_policy == {support: "unverified", ready: false} and
      (.certifications | type == "array") and
      all(.certifications[];
        .mainframe_version == $version and
        (.package | type == "string" and length > 0) and
        (.version | type == "string" and length > 0) and
        (.npm_integrity | test("^sha512-[A-Za-z0-9+/]+={0,2}$")) and
        (.platforms | type == "array" and length > 0) and
        (.support == "certified" or .support == "limited") and
        (.capabilities | type == "object" and length > 0) and
        (.limitations | type == "array") and
        (.support != "certified" or
          all(.capabilities | to_entries[]; .value == "verified"))
      ) and
      ([.certifications[] | .mainframe_version as $mf |
        .package as $package | .version as $pi |
        .platforms[] | [$mf, $package, $pi, .]] |
        length == (unique | length))
    ' "$compatibility_file" >/dev/null 2>&1; then
        _mainframe_release_readiness_error "$json" \
            'Pi compatibility contract is malformed or version-mismatched'
        return 1
    fi

    advertised_json="$("$jq_bin" -c '[.platforms[].id] | unique' \
        "$platforms_file")" || return 1
    certified_json="$("$jq_bin" -c \
        '[.certifications[] | select(.support == "certified") | .platforms[]] | unique' \
        "$compatibility_file")" || return 1
    unexpected_json="$("$jq_bin" -cn \
        --argjson advertised "$advertised_json" \
        --argjson certified "$certified_json" \
        '$certified - $advertised')" || return 1
    if [[ "$("$jq_bin" -r 'length' <<< "$unexpected_json")" -ne 0 ]]; then
        _mainframe_release_readiness_error "$json" \
            'Pi compatibility certifies a platform outside the advertised release contract'
        return 1
    fi
    certifications_json="$("$jq_bin" -c '
      [.certifications[] | {
        package,
        version,
        support,
        platforms: (.platforms | sort),
        evidence_date
      }]
    ' "$compatibility_file")" || return 1
    missing_json="$("$jq_bin" -cn \
        --argjson advertised "$advertised_json" \
        --argjson certified "$certified_json" \
        '$advertised - $certified')" || return 1

    report="$("$jq_bin" -cn \
        --arg version "$version" \
        --arg workflow_state "$workflow_state" \
        --argjson advertised "$advertised_json" \
        --argjson certified "$certified_json" \
        --argjson missing "$missing_json" \
        --argjson certifications "$certifications_json" '
      {
        schema_version: 1,
        kind: "mainframe-release-readiness",
        scope: "offline-checked-in-evidence-only",
        mainframe_version: $version,
        overall: {
          ready: false,
          status: "NOT_READY",
          reason: "external CI and distribution state are not proven by this offline report"
        },
        checked_in_contracts: {
          readable_and_valid: true,
          advertised_platforms: $advertised,
          pi: {
            exact_certifications: $certifications,
            certified_platforms: $certified,
            missing_advertised_platforms: $missing,
            complete_for_advertised_platforms: ($missing | length == 0)
          },
          workflow_definition: $workflow_state,
          release_candidate_definition: "present-not-candidate-proof",
          homebrew_formula_template: "present-not-publication-proof"
        },
        external_state: {
          exact_candidate_ci: "UNVERIFIED",
          public_immutable_release: "UNVERIFIED",
          homebrew_tap: "UNVERIFIED"
        },
        next_actions: [
          {
            id: "verify-local-candidate",
            command: "scripts/dev/release-candidate.sh --check",
            effect: "read-only candidate verification; does not publish"
          },
          {
            id: "prove-exact-platforms",
            action: "Run the exact-candidate Pi, shell-onboarding, native-host, and Homebrew CI matrices on every advertised tuple; ingest only green artifact-bound evidence."
          },
          {
            id: "promote-pi-evidence",
            action: "Add an exact Pi package/version/platform certification only after its archive-bound native run passes; unknown tuples must remain unverified."
          },
          {
            id: "publish-immutable-release",
            action: "After protected tagged-release gates pass, publish and independently verify the immutable runtime and evidence assets."
          },
          {
            id: "publish-homebrew-tap",
            action: "After the immutable release is verified, publish the formula to gtwatts/homebrew-mainframe and exercise a fresh Bash and zsh install."
          }
        ]
      }
    ')" || {
        _mainframe_release_readiness_error "$json" 'could not build readiness report'
        return 1
    }

    if [[ "$json" == true ]]; then
        printf '%s\n' "$report"
    else
        printf 'MAINFRAME Release Readiness\n'
        printf 'Scope: offline checked-in evidence only\n'
        printf 'Version: %s\n' "$version"
        printf 'Overall: NOT_READY\n'
        printf 'Checked-in contracts: valid\n'
        printf 'Pi exact certified platforms: '
        "$jq_bin" -r 'if length == 0 then "none" else join(", ") end' \
            <<< "$certified_json"
        printf 'Pi advertised platforms without exact certification: '
        "$jq_bin" -r 'if length == 0 then "none" else join(", ") end' \
            <<< "$missing_json"
        printf 'Exact-candidate CI: UNVERIFIED\n'
        printf 'Public immutable release: UNVERIFIED\n'
        printf 'Homebrew tap: UNVERIFIED\n'
        printf '\nExact next command (local, read-only):\n'
        printf '  scripts/dev/release-candidate.sh --check\n'
        printf '\nThen run the exact platform CI matrices, promote only artifact-bound evidence,\n'
        printf 'publish the protected immutable release, and verify a fresh Homebrew install.\n'
    fi

    # Offline checked-in evidence cannot prove remote execution or publication.
    return 2
}

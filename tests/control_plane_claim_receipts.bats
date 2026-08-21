#!/usr/bin/env bats

@test "typed content-bound claim receipt authority" {
    local project_root python_bin
    project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    python_bin="${MAINFRAME_PYTHON:-/usr/bin/python3}"
    [[ -x "$python_bin" ]] || python_bin="$(command -v python3)"

    run "$python_bin" -I -S -B "$project_root/tests/control_plane_claim_receipts.py"

    [[ "$status" -eq 0 ]]
}

@test "one exclusion registry separates packaged attestations from release subject" {
    local project_root package_inventory subject_inventory
    project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    package_inventory="$BATS_TEST_TMPDIR/package-inventory"
    subject_inventory="$BATS_TEST_TMPDIR/subject-inventory"

    run /bin/bash --noprofile --norc -p -c '
        set -euo pipefail
        root=$1
        source "$root/scripts/dev/release-payload.sh"
        mainframe_release_payload_files "$root" > "$2"
        mainframe_release_subject_files "$root" > "$3"
        mainframe_release_path_is_attestation_metadata \
            config/control-plane-claim-receipts/example.json
    ' mainframe-claim-inventory "$project_root" \
        "$package_inventory" "$subject_inventory"

    [[ "$status" -eq 0 ]]
    grep -Fxq 'config/control-plane-claim.json' "$package_inventory"
    ! grep -Fxq 'config/control-plane-claim.json' "$subject_inventory"
    grep -Fxq 'config/release-attestation-exclusions.txt' "$package_inventory"
    grep -Fxq 'config/release-attestation-exclusions.txt' "$subject_inventory"
}

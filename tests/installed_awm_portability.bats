#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    PYTHON_BIN="${MAINFRAME_CANARY_PYTHON:-$(command -v python3)}"
}

@test "installed AWM certifier snapshots the fixed kernel-owned XDG tree" {
    run "$PYTHON_BIN" -I -S -B - \
        "$PROJECT_ROOT/scripts/dev/certify-installed-awm-handoff.py" \
        "$BATS_TEST_TMPDIR" <<'PY'
import importlib.util
from pathlib import Path
import sys

tool = Path(sys.argv[1]).resolve(strict=True)
root = Path(sys.argv[2]).resolve(strict=True)
spec = importlib.util.spec_from_file_location("installed_awm_portability", tool)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

home = root / "home"
expected = (
    home / ".local" / "state" / "mainframe"
    / ".mainframe-control-plane-runtime"
    / "project-memory-adapter-state" / "awm"
)
assert module.project_memory_awm_root(home) == expected

environment = module.clean_environment(home, root / "tmp", "/usr/bin:/bin")
assert environment["XDG_STATE_HOME"] == str(home / ".local" / "state")
assert "AWM_ROOT" not in environment
PY
    [[ "$status" -eq 0 ]]
}

@test "AWM admits only an unmapped jq owner under a strict rootless UID map" {
    local mapped_root="$BATS_TEST_TMPDIR/mapped-root.uid_map"
    local codex_map="$BATS_TEST_TMPDIR/codex.uid_map"
    local rootless_map="$BATS_TEST_TMPDIR/rootless.uid_map"
    local nested_extra="$BATS_TEST_TMPDIR/nested-extra.uid_map"
    local owner_mapped="$BATS_TEST_TMPDIR/owner-mapped.uid_map"
    local inside_overlap="$BATS_TEST_TMPDIR/inside-overlap.uid_map"
    local outside_overlap="$BATS_TEST_TMPDIR/outside-overlap.uid_map"
    local range_overflow="$BATS_TEST_TMPDIR/range-overflow.uid_map"
    local zero_length="$BATS_TEST_TMPDIR/zero-length.uid_map"
    local malformed="$BATS_TEST_TMPDIR/malformed.uid_map"
    local overflow_uid="$BATS_TEST_TMPDIR/overflowuid"
    local overflow_invalid="$BATS_TEST_TMPDIR/overflowuid-invalid"

    printf '%s\n' '0 0 1' "$EUID $EUID 1" >"$mapped_root"
    printf '%s\n' "$EUID 0 1" >"$codex_map"
    printf '%s\n' "$EUID $EUID 1" >"$rootless_map"
    printf '%s\n' "$EUID 0 1" '60001 1001 1' >"$nested_extra"
    printf '%s\n' '0 65534 1' '60000 1001 1' >"$owner_mapped"
    printf '%s\n' '0 65534 2' '1 1001 1' >"$inside_overlap"
    printf '%s\n' '0 65534 2' '1001 65535 1' >"$outside_overlap"
    printf '%s\n' '4294967294 1001 2' >"$range_overflow"
    printf '%s\n' '0 1001 0' >"$zero_length"
    printf '%s\n' '0 1001 injected' >"$malformed"
    printf '%s\n' '60000' >"$overflow_uid"
    printf '%s\n' '60000' 'extra' >"$overflow_invalid"

    # Positional parameters are deliberately expanded only by the child Bash.
    # shellcheck disable=SC2016
    run "$BASH" --noprofile --norc -c '
        source "$1/lib/awm.sh"
        maps="$2"
        _awm_uid_map_range_is_nested_bwrap 1001 0 1 1001 || exit 8
        ! _awm_uid_map_range_is_nested_bwrap 0 0 1 0 || exit 9
        ! _awm_uid_map_range_is_nested_bwrap 1001 0 2 1001 || exit 32
        ! _awm_uid_map_range_is_nested_bwrap 1001 1 1 1001 || exit 33
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/mapped-root.uid_map" "$maps/overflowuid"
        [[ $? -eq 5 ]] || exit 10
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/codex.uid_map" "$maps/overflowuid" || exit 11
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/rootless.uid_map" "$maps/overflowuid" || exit 12
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/nested-extra.uid_map" "$maps/overflowuid"
        [[ $? -eq 5 ]] || exit 13
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/owner-mapped.uid_map" "$maps/overflowuid"
        [[ $? -eq 6 ]] || exit 14
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/inside-overlap.uid_map" "$maps/overflowuid"
        [[ $? -eq 4 ]] || exit 15
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/outside-overlap.uid_map" "$maps/overflowuid"
        [[ $? -eq 4 ]] || exit 16
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/range-overflow.uid_map" "$maps/overflowuid"
        [[ $? -eq 4 ]] || exit 17
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/zero-length.uid_map" "$maps/overflowuid"
        [[ $? -eq 4 ]] || exit 18
        _awm_uid_map_proves_unmapped_owner 60000 \
            "$maps/malformed.uid_map" "$maps/overflowuid"
        [[ $? -eq 4 ]] || exit 19
        _awm_uid_map_proves_unmapped_owner 60000 "$maps/missing.uid_map" \
            "$maps/overflowuid"
        [[ $? -eq 3 ]] || exit 35
        _awm_uid_map_proves_unmapped_owner 4294967295 \
            "$maps/rootless.uid_map" "$maps/overflowuid"
        [[ $? -eq 2 ]] || exit 20
        _awm_uid_map_proves_unmapped_owner 60000 "$maps/codex.uid_map" \
            "$maps/missing-overflowuid"
        [[ $? -eq 7 ]] || exit 21
        _awm_uid_map_proves_unmapped_owner 60000 "$maps/codex.uid_map" \
            "$maps/overflowuid-invalid"
        [[ $? -eq 7 ]] || exit 34
        _awm_uid_map_proves_unmapped_owner 60001 "$maps/codex.uid_map" \
            "$maps/overflowuid"
        [[ $? -eq 8 ]] || exit 22
        _awm_uid_map_proves_unmapped_owner() {
            [[ "$1" == 60000 && "$2" == /proc/self/uid_map ]] || return 2
        }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq || exit 23
        _awm_strict_jq_owner_is_trusted 60000 /usr/local/bin/jq
        [[ $? -eq 2 ]] || exit 24
        _awm_strict_jq_owner_is_trusted 12345 /usr/bin/jq
        [[ $? -eq 2 ]] || exit 25
        _awm_uid_map_proves_unmapped_owner() { return 3; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 3 ]] || exit 26
        _awm_uid_map_proves_unmapped_owner() { return 4; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 4 ]] || exit 27
        _awm_uid_map_proves_unmapped_owner() { return 5; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 5 ]] || exit 28
        _awm_uid_map_proves_unmapped_owner() { return 6; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 6 ]] || exit 29
        _awm_uid_map_proves_unmapped_owner() { return 7; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 7 ]] || exit 30
        _awm_uid_map_proves_unmapped_owner() { return 8; }
        _awm_strict_jq_owner_is_trusted 60000 /usr/bin/jq
        [[ $? -eq 8 ]] || exit 31
    ' bash "$PROJECT_ROOT" "$BATS_TEST_TMPDIR"
    if [[ "$status" -ne 0 ]]; then
        printf '# UID-map contract child exited %s\n' "$status" >&3
    fi
    [[ "$status" -eq 0 ]]
}

@test "checkpoint denial reports a bounded internal failure stage without content" {
    local test_tmp awm_root
    test_tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    awm_root="$test_tmp/staged-awm"

    # The child overrides one dependency at a time after creating a valid
    # checkpoint. No caller-controlled value may enter the diagnostic label.
    # shellcheck disable=SC2016
    run env AWM_ROOT="$awm_root" MAINFRAME_AGENT_NAME=stage-fixture \
        "$BASH" --noprofile --norc -c '
            source "$1/lib/awm.sh"
            awm_init stage-fixture >/dev/null || exit 20
            sid="$_AWM_SESSION_ID"
            awm_checkpoint stage_key stage-secret-value || exit 21

            (
                _awm_strict_jq_path() { return 1; }
                awm_get "$sid" stage_key >/dev/null 2>"$2/parser.err"
            ) && exit 22
            grep -Fq "stage=parser-admission-unavailable" \
                "$2/parser.err" || exit 23
            ! grep -Fq "stage-secret-value" "$2/parser.err" || exit 24

            (
                _awm_strict_jq_path() { printf "/usr/bin/false"; }
                awm_get "$sid" stage_key >/dev/null 2>"$2/parser-exec.err"
            ) && exit 38
            grep -Fq "stage=parser-execution-unavailable" \
                "$2/parser-exec.err" || exit 39
            ! grep -Fq "stage-secret-value" "$2/parser-exec.err" || exit 40

            (
                _awm_sha256_file() { return 1; }
                awm_get "$sid" stage_key >/dev/null 2>"$2/digest.err"
            ) && exit 25
            grep -Fq "stage=digest-tool-unavailable" "$2/digest.err" || exit 26
            ! grep -Fq "stage-secret-value" "$2/digest.err" || exit 27

            (
                _awm_sha256_file() {
                    printf "%064d" 0
                }
                awm_get "$sid" stage_key >/dev/null 2>"$2/mismatch.err"
            ) && exit 28
            grep -Fq "stage=digest-mismatch" "$2/mismatch.err" || exit 29
            ! grep -Fq "stage-secret-value" "$2/mismatch.err" || exit 30

            jq_path="$(_awm_strict_jq_path)" || exit 31
            meta="${_AWM_SESSION_DIR}/index/stage_key.json"
            "$jq_path" -cS ". + {unexpected: true}" "$meta" >"$2/meta.tmp" || exit 32
            chmod 600 "$2/meta.tmp" || exit 33
            mv -f -- "$2/meta.tmp" "$meta" || exit 34
            awm_get "$sid" stage_key >/dev/null 2>"$2/schema.err" && exit 35
            grep -Fq "stage=sidecar-schema-invalid" "$2/schema.err" || exit 36
            ! grep -Fq "stage-secret-value" "$2/schema.err" || exit 37
        ' bash "$PROJECT_ROOT" "$test_tmp"
    [[ "$status" -eq 0 ]]
}

@test "checkpoint created outside reads inside the Codex bubblewrap user namespace" {
    [[ "$(uname -s)" == Linux ]] || skip "Linux bubblewrap regression"
    [[ -x /usr/bin/bwrap ]] || skip "/usr/bin/bwrap unavailable"

    local test_tmp awm_root sid
    test_tmp="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    awm_root="$test_tmp/bwrap-awm"

    # Create the valid predecessor checkpoint before entering the sandbox, as
    # the native four-host certifier does between Gemini and Codex.
    # shellcheck disable=SC2016
    run env AWM_ROOT="$awm_root" MAINFRAME_AGENT_NAME=gemini-fixture \
        "$BASH" --noprofile --norc -c '
            source "$1/lib/awm.sh"
            awm_init gemini-fixture >/dev/null || exit 40
            awm_checkpoint chain.gemini namespace-secret >/dev/null || exit 41
            printf "%s" "$_AWM_SESSION_ID"
        ' bash "$PROJECT_ROOT"
    [[ "$status" -eq 0 ]]
    sid="$output"

    # Match the Codex sandbox topology: the root is read-only, /proc is from
    # the new user/PID namespaces, /dev is private, and all capabilities are
    # dropped. This is an end-to-end parser/path/digest proof rather than an
    # owner-helper mock.
    # shellcheck disable=SC2016
    run /usr/bin/bwrap \
        --new-session \
        --die-with-parent \
        --ro-bind / / \
        --dev /dev \
        --bind-try /dev/shm /dev/shm \
        --unshare-user \
        --unshare-pid \
        --unshare-ipc \
        --unshare-net \
        --proc /proc \
        --cap-drop ALL \
        --chdir "$PROJECT_ROOT" \
        "$BASH" --noprofile --norc -c '
            export AWM_ROOT="$1"
            source "$2/lib/awm.sh"
            awm_get "$3" chain.gemini
        ' bash "$awm_root" "$PROJECT_ROOT" "$sid"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "namespace-secret" ]]
}

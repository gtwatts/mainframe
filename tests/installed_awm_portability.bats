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

@test "AWM admits overflow-owned OS jq only when host root is unmapped" {
    local mapped_root="$BATS_TEST_TMPDIR/mapped-root.uid_map"
    local unmapped_root="$BATS_TEST_TMPDIR/unmapped-root.uid_map"
    local malformed="$BATS_TEST_TMPDIR/malformed.uid_map"

    printf '%s\n' '0 0 4294967295' >"$mapped_root"
    printf '%s\n' '0 1001 1' >"$unmapped_root"
    printf '%s\n' '0 1001 injected' >"$malformed"

    # Positional parameters are deliberately expanded only by the child Bash.
    # shellcheck disable=SC2016
    run "$BASH" --noprofile --norc -c '
        source "$1/lib/awm.sh"
        ! _awm_uid_map_excludes_host_root "$2" || exit 10
        _awm_uid_map_excludes_host_root "$3" || exit 11
        ! _awm_uid_map_excludes_host_root "$4" || exit 12
        _awm_uid_map_excludes_host_root() { [[ "$1" == /proc/self/uid_map ]]; }
        _awm_strict_jq_owner_is_trusted 65534 /usr/bin/jq || exit 13
        ! _awm_strict_jq_owner_is_trusted 65534 /usr/local/bin/jq || exit 14
        ! _awm_strict_jq_owner_is_trusted 12345 /usr/bin/jq || exit 15
    ' bash "$PROJECT_ROOT" "$mapped_root" "$unmapped_root" "$malformed"
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
            grep -Fq "stage=parser-unavailable" "$2/parser.err" || exit 23
            ! grep -Fq "stage-secret-value" "$2/parser.err" || exit 24

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
    # the new user namespace, and all capabilities are dropped.  This is an
    # end-to-end parser/path/digest proof rather than an owner-helper mock.
    # shellcheck disable=SC2016
    run /usr/bin/bwrap \
        --unshare-user \
        --ro-bind / / \
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

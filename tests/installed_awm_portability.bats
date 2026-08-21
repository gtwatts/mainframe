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

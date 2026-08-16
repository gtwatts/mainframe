#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-runner-platform.XXXXXX")"
    TRUSTED_BIN="$TEST_TMPDIR/trusted-bin"
    SHADOW_BIN="$TEST_TMPDIR/shadow-bin"
    TEST_NATIVE_DIR="$TEST_TMPDIR/native-host"
    mkdir -p "$TRUSTED_BIN" "$SHADOW_BIN" "$TEST_NATIVE_DIR"
    TEST_ASSERT="$TEST_NATIVE_DIR/assert-runner-platform.sh"
    cp "$PROJECT_ROOT/scripts/dev/native-host/assert-runner-platform.sh" "$TEST_ASSERT"
    cp "$PROJECT_ROOT/scripts/dev/native-host/release-platforms.json" "$TEST_NATIVE_DIR/"
    if [[ -f "$PROJECT_ROOT/scripts/dev/native-host/native-platform.sh" ]]; then
        cp "$PROJECT_ROOT/scripts/dev/native-host/native-platform.sh" "$TEST_NATIVE_DIR/"
    fi
    python3 - "$TEST_NATIVE_DIR" "$TRUSTED_BIN" <<'PY'
from pathlib import Path
import shlex
import sys

native_dir, trusted_bin = map(Path, sys.argv[1:])
replacements = (
    ("/usr/bin/uname", trusted_bin / "uname"),
    ("/usr/bin/getconf", trusted_bin / "getconf"),
    ("/usr/sbin/sysctl", trusted_bin / "sysctl"),
    ("/usr/bin/jq", trusted_bin / "jq"),
)
payloads = {
    path: path.read_text(encoding="utf-8")
    for path in sorted(native_dir.glob("*.sh"))
}
for needle, replacement in replacements:
    assert any(needle in payload for payload in payloads.values()), needle
    for path, payload in tuple(payloads.items()):
        payloads[path] = payload.replace(needle, shlex.quote(str(replacement)))
for path, payload in payloads.items():
    path.write_text(payload, encoding="utf-8")
    path.chmod(0o700)
PY
    cat > "$TRUSTED_BIN/jq" <<'EOF'
#!/usr/bin/env bash
id=""
last=""
while (( $# > 0 )); do
    if [[ "$1" == --arg && $# -ge 3 ]]; then
        [[ "$2" != id ]] || id="$3"
        shift 3
    else
        last="$1"
        shift
    fi
done
[[ -f "$last" && ! -L "$last" ]] || exit 1
case "$id" in
    Darwin-arm64-none|Darwin-x86_64-none|Linux-x86_64-glibc) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TRUSTED_BIN/jq"
    write_shadow_platform_stubs ShadowOS shadow_arch 'glibc 999.0'
    cd "$PROJECT_ROOT" || return 1
}

teardown() {
    rm -rf -- "$TEST_TMPDIR"
}

write_platform_stubs() {
    local os="$1" arch="$2" libc_report="${3:-}" translated="${4:-0}"
    local arm64_capable="${5:-}" long_bit="${6:-64}" cpu_brand="${7:-}"
    if [[ -z "$arm64_capable" ]]; then
        if [[ "$os" == Darwin && "$arch" == arm64 ]]; then
            arm64_capable=1
        else
            arm64_capable=missing
        fi
    fi
    if [[ -z "$cpu_brand" ]]; then
        if [[ "$os" == Darwin && "$arch" == x86_64 ]]; then
            cpu_brand='Intel(R) Xeon(R) CPU'
        elif [[ "$os" == Darwin && "$arch" == arm64 ]]; then
            cpu_brand='Apple M4'
        else
            cpu_brand=missing
        fi
    fi

    cat > "$TRUSTED_BIN/uname" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    -s) printf '%s\\n' '$os' ;;
    -m) printf '%s\\n' '$arch' ;;
    *) exit 64 ;;
esac
EOF
    cat > "$TRUSTED_BIN/getconf" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    LONG_BIT) printf '%s\\n' '$long_bit' ;;
    GNU_LIBC_VERSION)
        [[ '$libc_report' != missing ]] || exit 1
        printf '%s\\n' '$libc_report'
        ;;
    *) exit 64 ;;
esac
EOF
    cat > "$TRUSTED_BIN/sysctl" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == '-n' ]] || exit 64
case "\${2:-}" in
    sysctl.proc_translated)
        [[ '$translated' != missing ]] || exit 1
        [[ '$translated' != empty ]] || exit 0
        printf '%s\\n' '$translated'
        ;;
    hw.optional.arm64)
        [[ '$arm64_capable' != missing ]] || exit 1
        printf '%s\\n' '$arm64_capable'
        ;;
    machdep.cpu.brand_string)
        [[ '$cpu_brand' != missing ]] || exit 1
        printf '%s\\n' '$cpu_brand'
        ;;
    *) exit 64 ;;
esac
EOF
    chmod +x "$TRUSTED_BIN/uname" "$TRUSTED_BIN/getconf" "$TRUSTED_BIN/sysctl"
}

write_shadow_platform_stubs() {
    local os="$1" arch="$2" libc_report="$3"

    cat > "$SHADOW_BIN/uname" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    -s) printf '%s\\n' '$os' ;;
    -m) printf '%s\\n' '$arch' ;;
    *) exit 64 ;;
esac
EOF
    cat > "$SHADOW_BIN/getconf" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == 'GNU_LIBC_VERSION' ]] || exit 64
printf '%s\\n' '$libc_report'
EOF
    cat > "$SHADOW_BIN/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SHADOW_BIN/uname" "$SHADOW_BIN/getconf" "$SHADOW_BIN/jq"
}

@test "runner assertion rejects Rosetta as native Darwin x86_64" {
    write_platform_stubs Darwin x86_64 '' 1 1

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"translated under Rosetta"* ]]
}

@test "runner assertion rejects an x86 process on Apple Silicon without trusting one probe" {
    write_platform_stubs Darwin x86_64 '' missing 1

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"x86_64 process on Apple Silicon"* ]]
}

@test "runner assertion fails closed on malformed Darwin native-state output" {
    write_platform_stubs Darwin arm64 '' unknown 1

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Cannot establish native Darwin execution"* ]]
}

@test "runner assertion fails closed when Darwin native-state output is empty" {
    write_platform_stubs Darwin x86_64 '' empty 0

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Cannot establish native Darwin execution"* ]]
}

@test "native observation emits exactly OS and architecture without owning libc detection" {
    write_platform_stubs Darwin arm64 '' 0 1
    run observe_native
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Darwin\tarm64' ]]

    write_platform_stubs Darwin x86_64 '' missing 0
    run observe_native
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Darwin\tx86_64' ]]

    write_platform_stubs Linux x86_64 missing
    run observe_native
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Linux\tx86_64' ]]

    write_platform_stubs Linux aarch64 missing
    run observe_native
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Linux\taarch64' ]]
}

assert_platform() {
    env PATH="$SHADOW_BIN:$PATH" \
        "$TEST_ASSERT" "$@"
}

observe_native() {
    env PATH="$SHADOW_BIN:$PATH" \
        "$TEST_ASSERT" --observe-native
}

@test "runner assertion accepts every advertised release tuple" {
    write_platform_stubs Darwin arm64
    run assert_platform Darwin-arm64-none Darwin arm64 none
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Release runner verified: Darwin-arm64-none"* ]]

    write_platform_stubs Darwin x86_64 '' missing missing
    run assert_platform Darwin-x86_64-none Darwin x86_64 none
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Release runner verified: Darwin-x86_64-none"* ]]

    write_platform_stubs Linux x86_64 'glibc 2.39'
    run assert_platform Linux-x86_64-glibc Linux x86_64 glibc
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Release runner verified: Linux-x86_64-glibc"* ]]
}

@test "runner assertion refuses Darwin x86_64 when Intel hardware cannot be established" {
    write_platform_stubs Darwin x86_64 '' missing missing 64 missing

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Cannot establish native Darwin Intel hardware"* ]]
}

@test "runner assertion rejects an Apple Silicon CPU brand when native-state keys are absent" {
    write_platform_stubs Darwin x86_64 '' missing missing 64 'Apple M4'

    run observe_native

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Cannot establish native Darwin Intel hardware"* ]]
}

@test "advertised release validation resolves its catalog independently of CWD" {
    local foreign_cwd="$TEST_TMPDIR/foreign-cwd"
    mkdir -p "$foreign_cwd"
    write_platform_stubs Linux x86_64 'glibc 2.39'

    cd "$foreign_cwd"
    run assert_platform Linux-x86_64-glibc Linux x86_64 glibc

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Release runner verified: Linux-x86_64-glibc" ]]
}

@test "runner assertion uses fixed native identity and catalog probes" {
    run python3 - "$PROJECT_ROOT/scripts/dev/native-host" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
payload = "\n".join(
    path.read_text(encoding="utf-8")
    for path in (root / "assert-runner-platform.sh", root / "native-platform.sh")
    if path.exists()
)
for required in (
    "/usr/bin/uname",
    "/usr/bin/getconf",
    "/usr/sbin/sysctl",
    "/usr/bin/jq",
    "sysctl.proc_translated",
    "hw.optional.arm64",
    "machdep.cpu.brand_string",
):
    assert required in payload, required
PY
    [[ "$status" -eq 0 ]]
}

@test "runner assertion ignores PATH-shadowed uname identity probes" {
    write_platform_stubs Linux x86_64 'glibc 2.39'

    run assert_platform Linux-x86_64-glibc Linux x86_64 glibc

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Release runner verified: Linux-x86_64-glibc"* ]]
}

@test "runner assertion ignores a PATH-shadowed getconf result" {
    write_platform_stubs Linux x86_64 'musl 1.2.5'
    write_shadow_platform_stubs Linux x86_64 'glibc 999.0'

    run assert_platform Linux-x86_64-glibc Linux x86_64 glibc

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Expected a glibc Linux runner"* ]]
    [[ "$output" == *"musl 1.2.5"* ]]
}

@test "native observation ignores every PATH-shadowed identity probe" {
    write_platform_stubs Linux x86_64 'glibc 2.39'

    run observe_native

    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Linux\tx86_64' ]]
}

@test "runner assertion ignores PATH-shadowed catalog validation" {
    write_platform_stubs Linux arm64 'glibc 2.39'

    run observe_native
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'Linux\taarch64' ]]

    run assert_platform Linux-aarch64-glibc Linux aarch64 glibc

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Release runner tuple is not advertised"* ]]
}

@test "runner assertion rejects a runner-label architecture mismatch" {
    write_platform_stubs Darwin arm64

    run assert_platform Darwin-x86_64-none Darwin x86_64 none

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Release runner mismatch"* ]]
    [[ "$output" == *"got Darwin-arm64-none"* ]]
}

@test "runner assertion rejects a non-glibc Linux lane" {
    write_platform_stubs Linux x86_64 'musl 1.2.5'

    run assert_platform Linux-x86_64-glibc Linux x86_64 glibc

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"musl"* ]]
}

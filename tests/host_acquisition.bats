#!/usr/bin/env bats
# Explicit-network managed-host acquisition and anonymous-download contract.

load 'test_helper'

# Reuse the substantial synthetic native-package fixture without sourcing any
# @test declarations from the sibling suite. Keep this import bounded to the
# helper prefix before its first test so both files continue to parse alone.
_host_lifecycle_fixture_prefix="$(
    awk '/^setup\(\)/ { copying = 1 } /^@test / { exit } copying { print }' \
        "$BATS_TEST_DIRNAME/host_lifecycle.bats"
)"
eval "$_host_lifecycle_fixture_prefix"
unset _host_lifecycle_fixture_prefix
eval "$(declare -f setup | sed '1s/^setup /host_lifecycle_fixture_setup /')"
eval "$(declare -f teardown | sed '1s/^teardown /host_lifecycle_fixture_teardown /')"

setup() {
    host_lifecycle_fixture_setup
    PYTHON_BIN="$(command -v python3)"
    ACQUIRER="$RUNTIME_ROOT/scripts/dev/native-host/acquire-managed-package.py"
    DOWNLOAD_LOG="$TEST_DIR/acquisition-invocations.jsonl"
    MOCK_CONFIG="$RUNTIME_ROOT/scripts/dev/native-host/acquisition-mock.json"
    UNIT_SCRATCH="$TEST_DIR/unit scratch"
    UNIT_DESTINATION="$TEST_DIR/unit destination"
    mkdir -p "$UNIT_SCRATCH" "$UNIT_DESTINATION"
    chmod 700 "$UNIT_SCRATCH" "$UNIT_DESTINATION"
    UNIT_SCRATCH_IDENTITY="$(path_identity "$UNIT_SCRATCH")"
    UNIT_DESTINATION_IDENTITY="$(path_identity "$UNIT_DESTINATION")"

    export PYTHON_BIN ACQUIRER DOWNLOAD_LOG MOCK_CONFIG
    export UNIT_SCRATCH UNIT_DESTINATION
    export UNIT_SCRATCH_IDENTITY UNIT_DESTINATION_IDENTITY
}

teardown() {
    host_lifecycle_fixture_teardown
}

install_mock_acquirer() {
    "$JQ_BIN" -n \
        --arg source "$PACKAGE_DIR" \
        --arg log "$DOWNLOAD_LOG" \
        '{source: $source, log: $log}' > "$MOCK_CONFIG"
    chmod 600 "$MOCK_CONFIG"
    cat > "$ACQUIRER" <<'PY'
#!/usr/bin/env python3
"""Offline acquisition double for the host lifecycle integration tests."""

import hashlib
import json
import os
import pathlib
import shutil
import stat
import sys
import tarfile
from urllib.parse import urlsplit


def identity(path: pathlib.Path) -> str:
    metadata = path.stat(follow_symlinks=False)
    return f"{metadata.st_dev}:{metadata.st_ino}"


def fail(message: str) -> None:
    raise SystemExit(f"mock managed package acquisition failed: {message}")


if len(sys.argv) != 9:
    fail("expected eight arguments")

(
    url,
    scratch_raw,
    scratch_identity,
    destination_raw,
    destination_identity,
    integrity,
    package_name,
    package_version,
) = sys.argv[1:]
config = json.loads(pathlib.Path(__file__).with_name("acquisition-mock.json").read_text())
scratch = pathlib.Path(scratch_raw)
destination = pathlib.Path(destination_raw)
record = {
    "url": url,
    "scratch_identity": scratch_identity,
    "destination_identity": destination_identity,
    "integrity": integrity,
    "package_name": package_name,
    "package_version": package_version,
}
with open(config["log"], "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")

if identity(scratch) != scratch_identity or stat.S_IMODE(scratch.stat().st_mode) != 0o700:
    fail("scratch identity")
if identity(destination) != destination_identity or stat.S_IMODE(destination.stat().st_mode) != 0o700:
    fail("destination identity")
if any(scratch.iterdir()) or any(destination.iterdir()):
    fail("nonempty directory")
leaf = package_name.rsplit("/", 1)[-1]
expected_url = (
    f"https://registry.npmjs.org/{package_name}/-/"
    f"{leaf}-{package_version}.tgz"
)
if url != expected_url:
    fail("source policy")
archive = pathlib.Path(config["source"]) / pathlib.PurePosixPath(urlsplit(url).path).name
if not archive.is_file() or archive.is_symlink():
    fail("source archive")

# This double deliberately performs no package-manager or package execution.
# The real helper's anonymous same-descriptor behavior is covered below by the
# import harness; this integration double only supplies the authenticated
# synthetic bytes to the lifecycle's exact tree verification.
with tarfile.open(archive, "r:gz") as npm_archive:
    for member in npm_archive:
        parts = pathlib.PurePosixPath(member.name).parts
        if not parts or parts[0] != "package":
            fail("archive root")
        relative = parts[1:]
        if not relative:
            continue
        target = destination.joinpath(*relative)
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(target, 0o700)
            continue
        if not member.isfile():
            fail("archive member")
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        source = npm_archive.extractfile(member)
        if source is None:
            fail("archive member")
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            shutil.copyfileobj(source, output)
            output.flush()
            os.fsync(output.fileno())

package = json.loads((destination / "package.json").read_text())
if package.get("name") != package_name or package.get("version") != package_version:
    fail("package identity")
if any(scratch.iterdir()):
    fail("named scratch entry")
PY
    chmod 600 "$ACQUIRER"
}

assert_exact_codex_download_plan() {
    [[ -f "$DOWNLOAD_LOG" ]]
    [[ "$(count_lines "$DOWNLOAD_LOG")" == 2 ]]
    "$JQ_BIN" -se '
      length == 2 and
      (map(.url) | unique | length) == 2 and
      all(.[ ];
        .url == (
          "https://registry.npmjs.org/" + .package_name + "/-/" +
          (.package_name | split("/") | last) + "-" +
          .package_version + ".tgz"
        ) and
        (.scratch_identity | test("^[0-9]+:[0-9]+$")) and
        (.destination_identity | test("^[0-9]+:[0-9]+$")) and
        (.integrity | test("^sha512-[A-Za-z0-9+/]+={0,2}$"))
      )
    ' "$DOWNLOAD_LOG"
}

assert_no_prohibited_execution() {
    [[ ! -e "$COMMAND_LOG" ]]
    [[ ! -e "$VENDOR_LOG" ]]
}

assert_directory_empty() {
    local directory="$1"
    [[ -d "$directory" ]]
    [[ -z "$(find "$directory" -mindepth 1 -print -quit)" ]]
}

prepare_unit_archive() {
    local source
    UNIT_NAME='@openai/codex'
    UNIT_VERSION='0.146.0'
    UNIT_BASENAME='codex-0.146.0.tgz'
    UNIT_URL="https://registry.npmjs.org/$UNIT_NAME/-/$UNIT_BASENAME"
    source="$TEST_DIR/unit npm package"
    UNIT_ARCHIVE="$TEST_DIR/$UNIT_BASENAME"
    mkdir -p "$source/package/bin"
    "$JQ_BIN" -n \
        --arg name "$UNIT_NAME" \
        --arg version "$UNIT_VERSION" \
        '{name: $name, version: $version}' > "$source/package/package.json"
    printf '%s\n' 'unit payload' > "$source/package/bin/codex"
    chmod 644 "$source/package/package.json" "$source/package/bin/codex"
    make_npm_archive "$source" "$UNIT_ARCHIVE"
    UNIT_SRI="$(npm_sri_sha512 "$UNIT_ARCHIVE")"
    export UNIT_NAME UNIT_VERSION UNIT_BASENAME UNIT_URL UNIT_ARCHIVE UNIT_SRI
}

run_acquirer_case() {
    local scenario="$1" url="$2" scratch_identity="$3"
    local destination_identity="$4" integrity="$5"
    "$PYTHON_BIN" -I -S -B - \
        "$ACQUIRER" "$scenario" "$UNIT_ARCHIVE" "$url" \
        "$UNIT_SCRATCH" "$scratch_identity" \
        "$UNIT_DESTINATION" "$destination_identity" \
        "$integrity" "$UNIT_NAME" "$UNIT_VERSION" <<'PY'
import email.message
import importlib.util
import os
import pathlib
import sys

(
    module_path,
    scenario,
    body_path,
    url,
    scratch,
    scratch_identity,
    destination,
    destination_identity,
    integrity,
    package_name,
    package_version,
) = sys.argv[1:]
if not pathlib.Path(module_path).is_file():
    raise SystemExit("acquisition test harness: acquire-managed-package.py is missing")

spec = importlib.util.spec_from_file_location("managed_acquirer_under_test", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
body = pathlib.Path(body_path).read_bytes()


class FakeSocket:
    def __init__(self, peer: str) -> None:
        self.peer = peer

    def getpeername(self):
        return (self.peer, 443)

    def settimeout(self, _timeout):
        return None


class FakeResponse:
    def __init__(self, status, content, headers, read_error=False):
        self.status = status
        self.body = content
        self.position = 0
        self.headers = email.message.Message()
        for key, value in headers:
            self.headers[key] = value
        self.read_error = read_error

    def read(self, size=-1):
        # The security contract requires unlink-before-network: no scratch
        # pathname may be observable while response bytes are being consumed.
        if os.listdir(scratch):
            raise AssertionError("named-scratch-entry-visible-during-download")
        if self.read_error:
            raise OSError(f"synthetic read failure {url} {scratch} {destination}")
        if self.position >= len(self.body):
            return b""
        if size is None or size < 0:
            size = len(self.body) - self.position
        chunk = self.body[self.position : self.position + size]
        self.position += len(chunk)
        return chunk

    def close(self):
        return None


if scenario in {"declared-oversized", "stream-oversized"}:
    module.MAX_ARCHIVE_BYTES = 64
    if hasattr(module, "CHUNK_BYTES"):
        module.CHUNK_BYTES = 32

if scenario == "redirect":
    response = FakeResponse(
        302,
        b"",
        [("Location", "https://example.invalid/redirected.tgz")],
    )
elif scenario == "declared-oversized":
    response = FakeResponse(200, b"", [("Content-Length", "65")])
elif scenario == "stream-oversized":
    response = FakeResponse(200, b"x" * 65, [])
elif scenario == "io-error":
    response = FakeResponse(
        200,
        body,
        [("Content-Length", str(len(body)))],
        read_error=True,
    )
else:
    response = FakeResponse(200, body, [("Content-Length", str(len(body)))])


class FakeConnection:
    def __init__(self, *_args, **_kwargs):
        self.sock = None

    def connect(self):
        if scenario == "network-forbidden":
            raise AssertionError("network-called-before-policy-or-consent")
        peer = "127.0.0.1" if scenario == "private-peer" else "93.184.216.34"
        self.sock = FakeSocket(peer)

    def putrequest(self, *_args, **_kwargs):
        return None

    def putheader(self, *_args, **_kwargs):
        return None

    def endheaders(self):
        return None

    def request(self, *_args, **_kwargs):
        if self.sock is None:
            self.connect()

    def getresponse(self):
        return response

    def close(self):
        return None


module.http.client.HTTPSConnection = FakeConnection
sys.argv = [
    module_path,
    url,
    scratch,
    scratch_identity,
    destination,
    destination_identity,
    integrity,
    package_name,
    package_version,
]
raise SystemExit(module.main())
PY
}

@test "host install help exposes explicit mutually exclusive online and offline sources" {
    run mf host install --help

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"host install HOST"* ]]
    [[ "$output" == *"--download"* ]]
    [[ "$output" == *"--package-dir"* ]]
    [[ "$output" == *"--dry-run"*"--yes"*"--json"* ]]
}

@test "host install rejects a missing or conflicting source before network access" {
    install_mock_acquirer
    make_command_traps

    run mf host install codex --yes
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--download"* ]]
    [[ "$output" == *"--package-dir"* ]]
    [[ ! -e "$DOWNLOAD_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]

    run mf host install codex --download --package-dir "$PACKAGE_DIR" --yes
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"mutually exclusive"* || "$output" == *"exactly one"* ]]
    [[ ! -e "$DOWNLOAD_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]

    run mf host install codex --yes --json
    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e '
      .result == "error" and .source == null and
      .error.code == "source-required" and .network_attempted == false
    ' <<< "$output"

    run mf host install codex --download --package-dir "$PACKAGE_DIR" --yes --json
    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e '
      .result == "error" and .source == "conflict" and
      .error.code == "source-conflict" and .network_attempted == false
    ' <<< "$output"
    assert_no_prohibited_execution
}

@test "noninteractive online install without an action flag refuses before network" {
    install_mock_acquirer
    make_command_traps

    run mf host install codex --download

    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--yes"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ ! -e "$DOWNLOAD_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    assert_no_prohibited_execution
}

@test "JSON online install without an action flag returns a closed pre-network error" {
    install_mock_acquirer
    make_command_traps

    run mf host install codex --download --json

    [[ "$status" -eq 2 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .host == "codex" and
      .result == "error" and .changed == false and
      .source == "download" and .network_attempted == false and
      .error.code == "consent-required"
    ' <<< "$output"
    [[ "$output" != *"$TEST_HOME"* ]]
    [[ "$output" != *"$XDG_DATA_HOME"* ]]
    [[ "$output" != *"$PACKAGE_DIR"* ]]
    [[ ! -e "$DOWNLOAD_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    assert_no_prohibited_execution
}

@test "online dry-run acquires the exact registry plan and leaves no durable state" {
    make_codex_package_dir
    install_mock_acquirer
    make_command_traps

    run mf host install codex --download --dry-run --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .host == "codex" and
      .result == "would-install" and .changed == false and
      .source == "download" and .network_attempted == true and
      .archive_count == 2
    ' <<< "$output"
    assert_exact_codex_download_plan
    [[ ! -e "$XDG_DATA_HOME" ]]
    [[ -z "$(find "$TEST_DIR" -path "$PACKAGE_DIR" -prune -o \
        -type f -name '*.tgz' -print -quit)" ]]
    assert_no_prohibited_execution
}

@test "offline dry-run reports its source and never attempts network" {
    make_codex_package_dir
    install_mock_acquirer
    make_command_traps

    run mf host install codex --package-dir "$PACKAGE_DIR" --dry-run --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .host == "codex" and
      .result == "would-install" and .changed == false and
      .source == "package-dir" and .network_attempted == false and
      .archive_count == 2
    ' <<< "$output"
    [[ ! -e "$DOWNLOAD_LOG" ]]
    [[ ! -e "$XDG_DATA_HOME" ]]
    assert_no_prohibited_execution
}

@test "online yes installs the exact plan without curl npm or vendor execution" {
    make_codex_package_dir
    install_mock_acquirer
    make_command_traps

    run mf host install codex --download --yes --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .command == "host-install" and .host == "codex" and
      .result == "installed" and .changed == true and
      .source == "download" and .network_attempted == true and
      .archive_count == 2
    ' <<< "$output"
    assert_exact_codex_download_plan
    [[ -d "$CODEX_TARGET" && ! -L "$CODEX_TARGET" ]]
    [[ -f "$CODEX_TARGET/receipt.json" ]]
    [[ -z "$(find "$CODEX_TARGET" -type f -name '*.tgz' -print -quit)" ]]
    assert_no_prohibited_execution

    run mf host status codex --runtime managed --json
    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .hosts[0].managed.state == "ready" and
      .hosts[0].selection.source == "managed"
    ' <<< "$output"
}

@test "already installed online source returns without attempting network" {
    make_codex_package_dir
    install_mock_acquirer
    mf host install codex --package-dir "$PACKAGE_DIR" --yes >/dev/null
    rm -f "$DOWNLOAD_LOG"

    run mf host install codex --download --yes --json

    [[ "$status" -eq 0 ]]
    "$JQ_BIN" -e '
      .result == "already-installed" and .changed == false and
      .source == "download" and .network_attempted == false and
      .archive_count == 0
    ' <<< "$output"
    [[ ! -e "$DOWNLOAD_LOG" ]]
}

@test "acquirer rejects every noncanonical registry URL before network" {
    local candidate
    local -a candidates=(
        "http://registry.npmjs.org/@openai/codex/-/$UNIT_BASENAME"
        "https://registry.npmjs.org.evil.example/@openai/codex/-/$UNIT_BASENAME"
        "https://user@registry.npmjs.org/@openai/codex/-/$UNIT_BASENAME"
        "https://registry.npmjs.org:443/@openai/codex/-/$UNIT_BASENAME"
        "https://registry.npmjs.org/@openai/codex/-/$UNIT_BASENAME?token=secret"
        "https://registry.npmjs.org/@openai/codex/-/$UNIT_BASENAME#fragment"
    )
    prepare_unit_archive

    for candidate in "${candidates[@]}"; do
        run run_acquirer_case network-forbidden "$candidate" \
            "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"source-policy"* ]]
        [[ "$output" != *"network-called"* ]]
        assert_directory_empty "$UNIT_SCRATCH"
        assert_directory_empty "$UNIT_DESTINATION"
    done
}

@test "acquirer binds both scratch and destination directory identities before network" {
    prepare_unit_archive

    run run_acquirer_case network-forbidden "$UNIT_URL" \
        "0:0" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"scratch"* || "$output" == *"identity"* ||
       "$output" == *"directory-policy"* ]]
    [[ "$output" != *"network-called"* ]]

    run run_acquirer_case network-forbidden "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "0:0" "$UNIT_SRI"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"destination"* || "$output" == *"identity"* ||
       "$output" == *"directory-policy"* ]]
    [[ "$output" != *"network-called"* ]]
    assert_directory_empty "$UNIT_SCRATCH"
    assert_directory_empty "$UNIT_DESTINATION"
}

@test "acquirer rejects redirects and cleans anonymous scratch state" {
    prepare_unit_archive

    run run_acquirer_case redirect "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"redirect"* ]]
    assert_directory_empty "$UNIT_SCRATCH"
    assert_directory_empty "$UNIT_DESTINATION"
}

@test "acquirer rejects a private network peer" {
    prepare_unit_archive

    run run_acquirer_case private-peer "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"peer-policy"* || "$output" == *"private"* ]]
    assert_directory_empty "$UNIT_SCRATCH"
    assert_directory_empty "$UNIT_DESTINATION"
}

@test "acquirer rejects declared and streamed archives beyond the compressed bound" {
    local scenario
    prepare_unit_archive

    for scenario in declared-oversized stream-oversized; do
        run run_acquirer_case "$scenario" "$UNIT_URL" \
            "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"archive-too-large"* || "$output" == *"size"* ]]
        assert_directory_empty "$UNIT_SCRATCH"
        assert_directory_empty "$UNIT_DESTINATION"
    done
}

@test "acquirer removes anonymous scratch state on integrity mismatch" {
    prepare_unit_archive
    printf '%s\n' 'tampered after SRI calculation' >> "$UNIT_ARCHIVE"

    run run_acquirer_case success "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"integrity"* || "$output" == *"SHA-512"* ]]
    assert_directory_empty "$UNIT_SCRATCH"
    assert_directory_empty "$UNIT_DESTINATION"
}

@test "acquirer anonymously downloads and extracts the exact package tree" {
    local path
    prepare_unit_archive

    run run_acquirer_case success "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"

    [[ "$status" -eq 0 ]]
    assert_directory_empty "$UNIT_SCRATCH"
    [[ -f "$UNIT_DESTINATION/package.json" ]]
    [[ -f "$UNIT_DESTINATION/bin/codex" ]]
    [[ "$(< "$UNIT_DESTINATION/bin/codex")" == "unit payload" ]]
    "$JQ_BIN" -e \
        --arg name "$UNIT_NAME" --arg version "$UNIT_VERSION" \
        '.name == $name and .version == $version' \
        "$UNIT_DESTINATION/package.json"
    [[ -z "$(find "$UNIT_DESTINATION" -type f -name '*.tgz' -print -quit)" ]]
    while IFS= read -r path; do
        [[ ! -L "$path" ]]
        if [[ -d "$path" ]]; then
            [[ "$(file_mode "$path")" == 700 ]]
        else
            [[ "$(file_mode "$path")" == 600 ]]
            [[ "$(path_identity "$path")" =~ ^[0-9]+:[0-9]+$ ]]
        fi
    done < <(find "$UNIT_DESTINATION" -mindepth 1 -print)
}

@test "acquirer failures are one-line path-redacted and traceback-free" {
    local line_count
    prepare_unit_archive

    run run_acquirer_case io-error "$UNIT_URL" \
        "$UNIT_SCRATCH_IDENTITY" "$UNIT_DESTINATION_IDENTITY" "$UNIT_SRI"

    [[ "$status" -ne 0 ]]
    line_count="$(printf '%s\n' "$output" | wc -l | tr -d '[:space:]')"
    [[ "$line_count" == 1 ]]
    [[ "$output" == "managed package acquisition failed:"* ]]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"$UNIT_URL"* ]]
    [[ "$output" != *"$UNIT_SCRATCH"* ]]
    [[ "$output" != *"$UNIT_DESTINATION"* ]]
    assert_directory_empty "$UNIT_SCRATCH"
    assert_directory_empty "$UNIT_DESTINATION"
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    INPUT_DEFINITION="$PROJECT_ROOT/scripts/dev/native-host/certifier-inputs.json"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-release-evidence.XXXXXX")"
    FIXTURE_ROOT="$TEST_DIR/repository"
    EVIDENCE_DIR="$TEST_DIR/evidence"
    OUTPUT_DIR="$TEST_DIR/output"
    mkdir -p "$FIXTURE_ROOT" "$EVIDENCE_DIR" "$OUTPUT_DIR"

    python3 - "$PROJECT_ROOT" "$FIXTURE_ROOT" <<'PY'
import json
from pathlib import Path
import shutil
import stat
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
definition_path = source / "scripts/dev/native-host/certifier-inputs.json"
definition = json.loads(definition_path.read_text(encoding="utf-8"))
paths = [record["path"] for record in definition["files"]]
paths.append(".github/workflows/test.yml")
for relative in paths:
    source_path = source / relative
    if source_path.is_symlink() or not source_path.is_file():
        raise SystemExit(f"unsafe fixture source: {relative}")
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_path, target)
    target.chmod(stat.S_IMODE(source_path.stat().st_mode))
PY

    BUILDER="$FIXTURE_ROOT/scripts/dev/native-host/build-release-evidence.py"

    VERSION="$(tr -d '[:space:]' <"$FIXTURE_ROOT/VERSION")"
    TAG="v$VERSION"
    TAG_REF="refs/tags/$TAG"
    git -C "$FIXTURE_ROOT" init -q
    git -C "$FIXTURE_ROOT" config user.name "MAINFRAME Release Test"
    git -C "$FIXTURE_ROOT" config user.email "release-test@mainframe.invalid"
    git -C "$FIXTURE_ROOT" add .
    GIT_AUTHOR_DATE="2026-01-02T03:04:05Z" \
        GIT_COMMITTER_DATE="2026-01-02T03:04:05Z" \
        git -C "$FIXTURE_ROOT" commit -qm "release evidence fixture"
    git -C "$FIXTURE_ROOT" tag "$TAG"
    TAG_REF_SHA="$(git -C "$FIXTURE_ROOT" rev-parse "$TAG_REF")"
    TAG_COMMIT_SHA="$(git -C "$FIXTURE_ROOT" rev-parse "$TAG_REF^{commit}")"
    SOURCE_DATE_EPOCH="$(git -C "$FIXTURE_ROOT" show -s --format=%ct "$TAG_COMMIT_SHA")"

    ARCHIVE="$TEST_DIR/mainframe-$VERSION.tar.gz"
    jq -r '.files[].path' \
        "$FIXTURE_ROOT/scripts/dev/native-host/certifier-inputs.json" \
        | python3 -B "$FIXTURE_ROOT/scripts/dev/build-release-tar.py" \
            "$FIXTURE_ROOT" "$ARCHIVE"
    ARCHIVE_SHA="$(python3 - "$ARCHIVE" <<'PY'
import hashlib
from pathlib import Path
import sys

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

    python3 - \
        "$FIXTURE_ROOT/scripts/dev/native-host" \
        "$EVIDENCE_DIR" "$VERSION" "$ARCHIVE_SHA" "$TAG_COMMIT_SHA" <<'PY'
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import re
import sys
from typing import Any

native = Path(sys.argv[1])
output = Path(sys.argv[2])
version = sys.argv[3]
archive_sha = sys.argv[4]
tag_commit = sys.argv[5]


def resolve(root: dict[str, Any], reference: str) -> dict[str, Any]:
    current: Any = root
    for encoded in reference[2:].split("/"):
        part = encoded.replace("~1", "/").replace("~0", "~")
        current = current[part]
    return current


def merge(left: Any, right: Any) -> Any:
    if isinstance(left, dict) and isinstance(right, dict):
        combined = deepcopy(left)
        for key, value in right.items():
            combined[key] = merge(combined[key], value) if key in combined else deepcopy(value)
        return combined
    return deepcopy(right)


def patterned_value(pattern: str) -> str:
    known = {
        "^[0-9a-f]{64}$": "0" * 64,
        "^[0-9a-f]{40}$": "0" * 40,
        "^[0-9a-f]{12}$": "0" * 12,
        "^[0-9]+\\.[0-9]+\\.[0-9]+$": "1.0.0",
        "^sha512-[A-Za-z0-9+/]+={0,2}$": "sha512-QQ==",
        "^@openai/codex-(darwin|linux)-(arm64|x64)$": "@openai/codex-darwin-arm64",
        "^[0-9]+\\.[0-9]+\\.[0-9]+-(darwin|linux)-(arm64|x64)$": "1.0.0-darwin-arm64",
        "^@github/copilot-(darwin|linux|linuxmusl)-(arm64|x64)$": "@github/copilot-darwin-arm64",
        "^@anthropic-ai/claude-code-(darwin|linux)-(arm64|x64)(-musl)?$": "@anthropic-ai/claude-code-darwin-arm64",
        "^(gemini|codex|copilot|claude)$": "gemini",
        "^chain\\.[a-z]+$": "chain.seed",
        "^mainframe-[a-z]+-awm-chain$": "mainframe-gemini-awm-chain",
    }
    if pattern not in known:
        raise AssertionError(f"unhandled fixture pattern: {pattern}")
    value = known[pattern]
    assert re.search(pattern, value)
    return value


def materialize(schema: dict[str, Any], root: dict[str, Any]) -> Any:
    if "$ref" in schema:
        return materialize(resolve(root, schema["$ref"]), root)
    if "const" in schema:
        result: Any = deepcopy(schema["const"])
    elif "anyOf" in schema:
        result = materialize(schema["anyOf"][0], root)
    else:
        schema_type = schema.get("type")
        if schema_type == "object" or "properties" in schema:
            result = {}
            properties = schema.get("properties", {})
            required = set(schema.get("required", []))
            include_all = schema_type is None and not required
            for key, child in properties.items():
                if key in required or include_all:
                    result[key] = materialize(child, root)
        elif schema_type == "array":
            result = []
        elif schema_type == "string":
            if schema.get("format") == "date-time":
                result = "2026-01-02T03:04:05Z"
            elif "pattern" in schema:
                result = patterned_value(schema["pattern"])
            else:
                result = "x" * max(1, int(schema.get("minLength", 1)))
        elif schema_type == "integer":
            result = int(schema.get("minimum", 0))
        elif schema_type == "number":
            result = schema.get("minimum", 0)
        elif schema_type == "boolean":
            result = False
        elif schema_type == "null":
            result = None
        else:
            result = {}
    for conjunct in schema.get("allOf", []):
        result = merge(result, materialize(conjunct, root))
    return result


def permits(field_schema: dict[str, Any], expected: str) -> bool:
    if not field_schema:
        return True
    if "const" in field_schema:
        return field_schema["const"] == expected
    return any(
        isinstance(alternative, dict) and alternative.get("const") == expected
        for alternative in field_schema.get("anyOf", [])
    )


def select_platform(
    schema: dict[str, Any],
    operating_system: str,
    architecture: str,
    system_libc: str,
) -> dict[str, Any]:
    for conjunct in schema.get("allOf", []):
        for alternative in conjunct.get("anyOf", []):
            properties = alternative.get("properties", {})
            if (
                permits(properties.get("os", {}), operating_system)
                and permits(properties.get("arch", {}), architecture)
                and permits(properties.get("system_libc", {}), system_libc)
                and permits(properties.get("libc", {}), system_libc)
            ):
                return alternative
    return {}


platforms = json.loads(
    (native / "release-platforms.json").read_text(encoding="utf-8")
)["platforms"]
schema_names = {
    "gemini": "evidence.schema.json",
    "codex": "codex-evidence.schema.json",
    "copilot": "copilot-evidence.schema.json",
    "claude": "claude-evidence.schema.json",
}
for host, schema_name in schema_names.items():
    schema = json.loads((native / schema_name).read_text(encoding="utf-8"))
    for release_platform in platforms:
        operating_system = release_platform["os"]
        architecture = release_platform["arch"]
        system_libc = release_platform["system_libc"]
        document = materialize(schema, schema)
        platform = select_platform(
            schema, operating_system, architecture, system_libc
        )
        if platform:
            document = merge(document, materialize(platform, schema))
        document.update(
            {
                "host": host,
                "mainframe_version": version,
                "archive_sha256": archive_sha,
                "archive_origin": "workspace-build",
                "source_git_commit": tag_commit,
                "source_git_dirty": False,
                "os": operating_system,
                "arch": architecture,
                "system_libc": system_libc,
                "certification": "execution-certified",
                "certified_at": "2026-01-02T03:04:05Z",
            }
        )
        if "libc" in document:
            document["libc"] = system_libc
        target = output / f"{host}-{release_platform['id']}.json"
        target.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")

awm_schema = json.loads((native / "awm-chain-evidence.schema.json").read_text(encoding="utf-8"))
for release_platform in platforms:
    operating_system = release_platform["os"]
    architecture = release_platform["arch"]
    system_libc = release_platform["system_libc"]
    document = materialize(awm_schema, awm_schema)
    platform_schema = awm_schema["properties"]["platform"]
    platform_choice = select_platform(
        platform_schema, operating_system, architecture, system_libc
    )
    if platform_choice:
        document["platform"] = merge(
            document["platform"], materialize(platform_choice, awm_schema)
        )
    document["certification"] = "native-awm-chain-execution-certified"
    document["certified_at"] = "2026-01-02T03:04:05Z"
    document["mainframe"]["version"] = version
    document["mainframe"]["archive_sha256"] = archive_sha
    document["mainframe"]["archive_origin"] = "external-input"
    document["platform"].update(
        {
            "os": operating_system,
            "arch": architecture,
            "libc": system_libc,
            "system_libc": system_libc,
        }
    )
    target = output / f"awm-{release_platform['id']}.json"
    target.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

    MANIFEST="$OUTPUT_DIR/mainframe-$VERSION.release-evidence.json"
    BUNDLE="$OUTPUT_DIR/mainframe-$VERSION.release-evidence.tar.gz"
    COMMON_ARGS=(
        --repo-root "$FIXTURE_ROOT"
        --repository gtwatts/mainframe
        --version "$VERSION"
        --tag "$TAG"
        --tag-ref "$TAG_REF"
        --tag-ref-sha "$TAG_REF_SHA"
        --tag-commit-sha "$TAG_COMMIT_SHA"
        --workflow-run-id 123456789
        --workflow-run-attempt 1
        --source-date-epoch "$SOURCE_DATE_EPOCH"
        --archive "$ARCHIVE"
        --manifest "$MANIFEST"
        --bundle "$BUNDLE"
    )
    EVIDENCE_ARGS=(
        --safety-evidence "$EVIDENCE_DIR/claude-Linux-x86_64-glibc.json"
        --safety-evidence "$EVIDENCE_DIR/gemini-Darwin-arm64-none.json"
        --safety-evidence "$EVIDENCE_DIR/copilot-Darwin-x86_64-none.json"
        --safety-evidence "$EVIDENCE_DIR/codex-Linux-x86_64-glibc.json"
        --safety-evidence "$EVIDENCE_DIR/claude-Darwin-arm64-none.json"
        --safety-evidence "$EVIDENCE_DIR/gemini-Linux-x86_64-glibc.json"
        --safety-evidence "$EVIDENCE_DIR/copilot-Linux-x86_64-glibc.json"
        --safety-evidence "$EVIDENCE_DIR/codex-Darwin-arm64-none.json"
        --safety-evidence "$EVIDENCE_DIR/claude-Darwin-x86_64-none.json"
        --safety-evidence "$EVIDENCE_DIR/gemini-Darwin-x86_64-none.json"
        --safety-evidence "$EVIDENCE_DIR/copilot-Darwin-arm64-none.json"
        --safety-evidence "$EVIDENCE_DIR/codex-Darwin-x86_64-none.json"
        --awm-evidence "$EVIDENCE_DIR/awm-Linux-x86_64-glibc.json"
        --awm-evidence "$EVIDENCE_DIR/awm-Darwin-x86_64-none.json"
        --awm-evidence "$EVIDENCE_DIR/awm-Darwin-arm64-none.json"
    )
}

teardown() {
    chmod -R u+w "$TEST_DIR" 2>/dev/null || true
    rm -rf -- "$TEST_DIR"
}

create_evidence() {
    python3 "$BUILDER" create "${COMMON_ARGS[@]}" "${EVIDENCE_ARGS[@]}"
}

create_evidence_without_source() {
    local excluded="$1"
    local -a filtered=()
    local index=0
    while ((index < ${#EVIDENCE_ARGS[@]})); do
        if [[ "${EVIDENCE_ARGS[$((index + 1))]}" != "$excluded" ]]; then
            filtered+=("${EVIDENCE_ARGS[$index]}" "${EVIDENCE_ARGS[$((index + 1))]}")
        fi
        index=$((index + 2))
    done
    python3 "$BUILDER" create "${COMMON_ARGS[@]}" "${filtered[@]}"
}

verify_evidence() {
    python3 "$BUILDER" verify "${COMMON_ARGS[@]}"
}

mutate_runtime_archive() {
    python3 - "$ARCHIVE" "$1" <<'PY'
import io
from pathlib import Path
import sys
import tarfile

path = Path(sys.argv[1])
mutation = sys.argv[2]
with tarfile.open(path, "r:gz") as source:
    entries = []
    for member in source:
        contents = source.extractfile(member)
        assert contents is not None
        entries.append((member.name, member.mode, contents.read()))

control = "scripts/dev/native-host/certify-codex.sh"
output = io.BytesIO()
with tarfile.open(fileobj=output, mode="w:gz", format=tarfile.USTAR_FORMAT) as target:
    for name, mode, contents in entries:
        if mutation == "missing" and name == control:
            continue
        if mutation == "tamper" and name == control:
            replacement = b"!" if contents[:1] == b"#" else b"#"
            contents = replacement + contents[1:]
        info = tarfile.TarInfo(name)
        info.size = len(contents)
        info.mode = mode
        info.mtime = 0
        info.uid = info.gid = 0
        target.addfile(info, io.BytesIO(contents))
    if mutation == "duplicate":
        contents = next(contents for name, _, contents in entries if name == control)
        info = tarfile.TarInfo(control)
        info.size = len(contents)
        info.mode = 0o755
        info.mtime = 0
        info.uid = info.gid = 0
        target.addfile(info, io.BytesIO(contents))
    elif mutation == "traversal":
        info = tarfile.TarInfo("../escape")
        info.size = 1
        info.mode = 0o644
        info.mtime = 0
        info.uid = info.gid = 0
        target.addfile(info, io.BytesIO(b"x"))
    elif mutation == "symlink":
        info = tarfile.TarInfo("archive-link")
        info.type = tarfile.SYMTYPE
        info.linkname = control
        info.mode = 0o644
        info.mtime = 0
        info.uid = info.gid = 0
        target.addfile(info)
path.write_bytes(output.getvalue())
PY
}

@test "certifier input definition captures the exact transitive control-file graph" {
    run python3 - "$INPUT_DEFINITION" <<'PY'
import json
from pathlib import Path
import sys

definition = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
actual = [record["path"] for record in definition["files"]]
expected = [
    "VERSION",
    "lib/host_lifecycle.sh",
    "lib/host_runtime.sh",
    "scripts/build-release-archive.sh",
    "scripts/dev/build-release-tar.py",
    "scripts/dev/certify-native-awm-chain.sh",
    "scripts/dev/certify-native-host.sh",
    "scripts/dev/certify-shell-onboarding.sh",
    "scripts/dev/native-host/acquire-managed-package.py",
    "scripts/dev/native-host/assert-runner-platform.sh",
    "scripts/dev/native-host/awm-chain-evidence.schema.json",
    "scripts/dev/native-host/build-release-evidence.py",
    "scripts/dev/native-host/certifier-inputs.json",
    "scripts/dev/native-host/certify-claude.sh",
    "scripts/dev/native-host/certify-codex.sh",
    "scripts/dev/native-host/certify-copilot.sh",
    "scripts/dev/native-host/claude-evidence.schema.json",
    "scripts/dev/native-host/claude-messages-server.py",
    "scripts/dev/native-host/codex-evidence.schema.json",
    "scripts/dev/native-host/codex-responses-server.py",
    "scripts/dev/native-host/copilot-chat-completions-server.py",
    "scripts/dev/native-host/copilot-evidence.schema.json",
    "scripts/dev/native-host/evidence.schema.json",
    "scripts/dev/native-host/extract-managed-package.py",
    "scripts/dev/native-host/fixtures/claude-awm-chain.messages.json",
    "scripts/dev/native-host/fixtures/claude-destroy.messages.json",
    "scripts/dev/native-host/fixtures/codex-awm-chain.responses.json",
    "scripts/dev/native-host/fixtures/codex-destroy.responses.json",
    "scripts/dev/native-host/fixtures/copilot-awm-chain.chat-completions.json",
    "scripts/dev/native-host/fixtures/copilot-destroy.chat-completions.json",
    "scripts/dev/native-host/fixtures/gemini-awm-chain.responses.jsonl",
    "scripts/dev/native-host/fixtures/gemini-destroy.responses.jsonl",
    "scripts/dev/native-host/hash-package-tree.py",
    "scripts/dev/native-host/hosts.json",
    "scripts/dev/native-host/managed-host-fs.py",
    "scripts/dev/native-host/package-lock.json",
    "scripts/dev/native-host/package.json",
    "scripts/dev/native-host/release-evidence.schema.json",
    "scripts/dev/native-host/release-platforms.json",
    "scripts/dev/native-host/safe-extract.py",
    "scripts/dev/native-host/validate-evidence.py",
    "scripts/dev/native-host/validate-native-executable.py",
    "scripts/dev/release-payload.sh",
    "scripts/dev/shell-onboarding-evidence.schema.json",
    "scripts/generate-sbom.sh",
]
assert definition["schema_version"] == 1
assert actual == expected
assert len(actual) == len(set(actual)) == 45
assert all(set(record) == {"path", "role"} for record in definition["files"])
assert next(
    record["role"]
    for record in definition["files"]
    if record["path"] == "scripts/dev/native-host/assert-runner-platform.sh"
) == "platform-validator"
assert next(
    record["role"]
    for record in definition["files"]
    if record["path"] == "scripts/dev/native-host/release-platforms.json"
) == "release-platform-definition"
assert next(
    record["role"]
    for record in definition["files"]
    if record["path"] == "scripts/dev/native-host/validate-native-executable.py"
) == "native-executable-validator"
assert next(
    record["role"]
    for record in definition["files"]
    if record["path"] == "scripts/dev/certify-shell-onboarding.sh"
) == "certifier-harness"
assert next(
    record["role"]
    for record in definition["files"]
    if record["path"] == "scripts/dev/shell-onboarding-evidence.schema.json"
) == "evidence-schema"
print("exact 45-file certifier input graph")
PY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "exact 45-file certifier input graph" ]]
}

@test "create and verify are deterministic and bind exact release evidence" {
    run create_evidence
    [[ "$status" -eq 0 ]]
    first_result="$output"
    [[ "$(jq -r '.status' <<<"$first_result")" == "created" ]]

    run verify_evidence
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r '.status' <<<"$output")" == "valid" ]]

    run jq -e \
        --arg archive_sha "$ARCHIVE_SHA" \
        --arg commit "$TAG_COMMIT_SHA" '
      .kind == "mainframe-release-evidence-manifest" and
      .archive.sha256 == $archive_sha and
      .release.tag_commit_sha == $commit and
      (.certifier_input_bundle.files | length) == 45 and
      ([.platform_matrix.platforms[].id] | sort) == [
        "Darwin-arm64-none", "Darwin-x86_64-none", "Linux-x86_64-glibc"
      ] and
      (.evidence.safety | length) == 12 and
      (.evidence.awm_chain | length) == 3 and
      ([.evidence.safety[] |
          .host + ":" + .os + "-" + .arch + "-" + .system_libc] | sort) == [
        "claude:Darwin-arm64-none", "claude:Darwin-x86_64-none", "claude:Linux-x86_64-glibc",
        "codex:Darwin-arm64-none", "codex:Darwin-x86_64-none", "codex:Linux-x86_64-glibc",
        "copilot:Darwin-arm64-none", "copilot:Darwin-x86_64-none", "copilot:Linux-x86_64-glibc",
        "gemini:Darwin-arm64-none", "gemini:Darwin-x86_64-none", "gemini:Linux-x86_64-glibc"
      ] and
      ([.evidence.awm_chain[] | .os + "-" + .arch + "-" + .system_libc] | sort) == [
        "Darwin-arm64-none", "Darwin-x86_64-none", "Linux-x86_64-glibc"
      ] and
      all(.evidence.safety[];
        .libc == .system_libc and
        .archive_origin == "workspace-build" and
        .source_git_commit == $commit and .source_git_dirty == false) and
      all(.evidence.awm_chain[];
        .libc == .system_libc and .archive_origin == "external-input")
    ' "$MANIFEST"
    [[ "$status" -eq 0 ]]

    run bash -c 'tar -tzf "$1" | wc -l | tr -d "[:space:]"' _ "$BUNDLE"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "16" ]]

    first_manifest_sha="$(jq -r '.manifest_sha256' <<<"$first_result")"
    first_bundle_sha="$(jq -r '.bundle_sha256' <<<"$first_result")"
    python3 - "$MANIFEST" "$BUNDLE" <<'PY'
from pathlib import Path
import sys

for value in sys.argv[1:]:
    Path(value).unlink()
PY
    run create_evidence
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r '.manifest_sha256' <<<"$output")" == "$first_manifest_sha" ]]
    [[ "$(jq -r '.bundle_sha256' <<<"$output")" == "$first_bundle_sha" ]]
}

@test "create rejects tag-bound input drift and preserves no-clobber outputs" {
    printf '\n# uncommitted workflow drift\n' >>"$FIXTURE_ROOT/.github/workflows/test.yml"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release workflow does not match the peeled tag commit"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "create binds exact control bytes and rejects unsafe runtime archive members" {
    pristine="$TEST_DIR/pristine-runtime.tar.gz"
    cp "$ARCHIVE" "$pristine"

    mutate_runtime_archive tamper
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not byte-equal to the peeled tag input"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]

    cp "$pristine" "$ARCHIVE"
    mutate_runtime_archive missing
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"missing certifier control members"* ]]

    cp "$pristine" "$ARCHIVE"
    mutate_runtime_archive duplicate
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate release archive member"* ]]

    cp "$pristine" "$ARCHIVE"
    mutate_runtime_archive traversal
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release archive member is unsafe"* ]]

    cp "$pristine" "$ARCHIVE"
    mutate_runtime_archive symlink
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release archive member is not a regular file"* ]]
}

@test "create preserves the AWM external-input boundary" {
    python3 - "$EVIDENCE_DIR/awm-Linux-x86_64-glibc.json" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
document = json.loads(path.read_text(encoding="utf-8"))
document["mainframe"]["archive_origin"] = "workspace-build"
path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive_origin"* ]]
    [[ "$output" == *"external-input"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "create requires exactly twelve safety and three AWM platform certificates" {
    run create_evidence_without_source \
        "$EVIDENCE_DIR/gemini-Darwin-x86_64-none.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"requires exactly 12 safety certificates, got 11"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]

    run create_evidence_without_source \
        "$EVIDENCE_DIR/awm-Darwin-x86_64-none.json"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"requires exactly 3 AWM certificates, got 2"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "create rejects duplicate safety and AWM platform tuples" {
    safety_target="$EVIDENCE_DIR/gemini-Darwin-x86_64-none.json"
    cp "$safety_target" "$TEST_DIR/safety-target.json"
    cp "$EVIDENCE_DIR/gemini-Darwin-arm64-none.json" "$safety_target"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate safety evidence coverage: gemini/Darwin-arm64-none"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]

    cp "$TEST_DIR/safety-target.json" "$safety_target"
    awm_target="$EVIDENCE_DIR/awm-Darwin-x86_64-none.json"
    cp "$EVIDENCE_DIR/awm-Darwin-arm64-none.json" "$awm_target"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"duplicate AWM evidence coverage: Darwin-arm64-none"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "create rejects missing or disagreeing normalized system_libc fields" {
    evidence="$EVIDENCE_DIR/gemini-Darwin-arm64-none.json"
    cp "$evidence" "$TEST_DIR/system-libc-evidence.json"
    jq 'del(.system_libc)' "$evidence" >"$evidence.tmp"
    mv "$evidence.tmp" "$evidence"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed schema validation"* ]]
    [[ "$output" == *"system_libc"* ]]

    cp "$TEST_DIR/system-libc-evidence.json" "$evidence"
    evidence="$EVIDENCE_DIR/copilot-Linux-x86_64-glibc.json"
    jq '.system_libc = "musl"' "$evidence" >"$evidence.tmp"
    mv "$evidence.tmp" "$evidence"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed schema validation"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "create rejects a musl tuple that is not advertised for this release" {
    evidence="$EVIDENCE_DIR/gemini-Linux-x86_64-glibc.json"
    jq '.system_libc = "musl"' "$evidence" >"$evidence.tmp"
    mv "$evidence.tmp" "$evidence"
    run create_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"platform is not advertised for this release"* ]]
    [[ "$output" == *"Linux-x86_64-musl"* ]]
    [[ ! -e "$MANIFEST" ]]
    [[ ! -e "$BUNDLE" ]]
}

@test "verify rejects certificate-byte tampering in an otherwise canonical bundle" {
    run create_evidence
    [[ "$status" -eq 0 ]]
    python3 - "$BUILDER" "$MANIFEST" "$BUNDLE" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
builder_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
bundle_path = Path(sys.argv[3])
spec = importlib.util.spec_from_file_location("release_evidence_builder", builder_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
manifest_bytes = manifest_path.read_bytes()
manifest = json.loads(manifest_bytes)
names = {"release-evidence.json"}
names.update(record["path"] for record in manifest["evidence"]["safety"])
names.update(record["path"] for record in manifest["evidence"]["awm_chain"])
epoch = manifest["release"]["source_date_epoch"]
entries = module.parse_bundle(bundle_path.read_bytes(), names, epoch)
target = "evidence/safety/gemini-Darwin-arm64-none.json"
entries[target] += b" "
bundle_path.write_bytes(
    module.stored_gzip(module.build_tar_stream(entries, epoch), epoch)
)
PY
    run verify_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"records do not match the bundled certificate bytes"* ]]
}

@test "verify rejects traversal and non-regular bundle members" {
    run create_evidence
    [[ "$status" -eq 0 ]]
    python3 - "$BUNDLE" "$SOURCE_DATE_EPOCH" traversal <<'PY'
import io
from pathlib import Path
import sys
import tarfile

path = Path(sys.argv[1])
epoch = int(sys.argv[2])
mode = sys.argv[3]
with tarfile.open(path, "r:gz") as source:
    entries = [(member.name, source.extractfile(member).read()) for member in source]
output = io.BytesIO()
with tarfile.open(fileobj=output, mode="w:gz", format=tarfile.USTAR_FORMAT) as target:
    for index, (name, contents) in enumerate(entries):
        if index == 0:
            # Keep the exact 16-member ceiling while substituting one malicious
            # member, so path/type validation remains independently exercised.
            continue
        info = tarfile.TarInfo(name)
        info.size = len(contents)
        info.mode = 0o644
        info.mtime = epoch
        info.uid = info.gid = 0
        target.addfile(info, io.BytesIO(contents))
    bad = tarfile.TarInfo("../escape.json" if mode == "traversal" else "evidence/link")
    bad.mode = 0o644
    bad.mtime = epoch
    bad.uid = bad.gid = 0
    if mode == "traversal":
        bad.size = 3
        target.addfile(bad, io.BytesIO(b"{}\n"))
    else:
        bad.type = tarfile.SYMTYPE
        bad.linkname = "release-evidence.json"
        target.addfile(bad)
path.write_bytes(output.getvalue())
PY
    run verify_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"unsafe"* ]]

    python3 - "$MANIFEST" "$BUNDLE" "$SOURCE_DATE_EPOCH" <<'PY'
import io
import json
from pathlib import Path
import sys
import tarfile

manifest_path = Path(sys.argv[1])
bundle_path = Path(sys.argv[2])
epoch = int(sys.argv[3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
entries = {"release-evidence.json": manifest_path.read_bytes()}
for record in manifest["evidence"]["safety"] + manifest["evidence"]["awm_chain"]:
    # The earlier malicious rewrite retained every original regular member.
    pass
output = io.BytesIO()
with tarfile.open(fileobj=output, mode="w:gz", format=tarfile.USTAR_FORMAT) as target:
    info = tarfile.TarInfo("evidence/link")
    info.type = tarfile.SYMTYPE
    info.linkname = "release-evidence.json"
    info.mode = 0o644
    info.mtime = epoch
    info.uid = info.gid = 0
    target.addfile(info)
bundle_path.write_bytes(output.getvalue())
PY
    run verify_evidence
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a regular file"* ]]
}

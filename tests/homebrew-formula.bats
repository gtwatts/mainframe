#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    PROJECT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
    GENERATOR="$PROJECT_ROOT/scripts/dev/generate-homebrew-formula.sh"
    CANDIDATE_BUILDER="$PROJECT_ROOT/scripts/dev/release-candidate.sh"
    CANDIDATE_VERIFIER="$PROJECT_ROOT/scripts/dev/verify-release-candidate.py"
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-homebrew-formula.XXXXXX")"
    ARCHIVE="$TEST_DIR/mainframe-${PROJECT_VERSION}.tar.gz"
    CHECKSUM="${ARCHIVE}.sha256"
    SBOM="$TEST_DIR/mainframe-${PROJECT_VERSION}.sbom.json"
    FORMULA="$TEST_DIR/mainframe.rb"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
    PYTHON_BIN="$(command -v python3)"

    if ! "$BASH_BIN" -c '
        ((BASH_VERSINFO[0] > 4)) ||
        ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))
    ' >/dev/null 2>&1; then
        skip "Bash 4.4+ is required"
    fi
}

create_release_trust_fixture() {
    local root="$TEST_DIR/release-trust"
    mkdir -p "$root/scripts/dev" "$root/output"
    cp "$CANDIDATE_BUILDER" "$root/scripts/dev/release-candidate.sh"
    cp "$PROJECT_ROOT/scripts/dev/release-runtime.sh" \
        "$root/scripts/dev/release-runtime.sh"
    chmod +x "$root/scripts/dev/release-candidate.sh"
    printf '%s\n' '10.2.0' > "$root/VERSION"
    printf '%s\n' \
        '{' \
        '  "version": "10.2.0",' \
        '  "name": "@gtwatts/mainframe-pi"' \
        '}' > "$root/package.json"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'MAINFRAME_RELEASE_PAYLOAD_ROOTS=(VERSION package.json)' \
        'mainframe_release_payload_files() {' \
        '  printf "%s\\n" VERSION package.json' \
        '}' \
        'mainframe_release_payload_git_pathspecs() {' \
        '  printf ":(top,literal)%s\\0" VERSION package.json' \
        '}' > "$root/scripts/dev/release-payload.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ -n "${MAINFRAME_RELEASE_TRUST_ENV_MARKER:-}" ]]; then' \
        '  for variable in PERL5OPT PERL5LIB PERLLIB RUBYOPT RUBYLIB NODE_OPTIONS NODE_PATH NODE_REDIRECT_WARNINGS NODE_REPL_HISTORY NODE_V8_COVERAGE MAINFRAME_ROOT MAINFRAME_MANIFEST_PATH MAINFRAME_INVOCATION_INDEX_PATH MAINFRAME_LSP_META_PATH; do' \
        '    if [[ -n "${!variable+x}" ]]; then' \
        '      printf "%s\\n" "$variable" >> "$MAINFRAME_RELEASE_TRUST_ENV_MARKER"' \
        '    fi' \
        '  done' \
        '  if env | grep -Eq "^(BASHOPTS|SHELLOPTS)="; then' \
        '    printf "Bash option export\\n" >> "$MAINFRAME_RELEASE_TRUST_ENV_MARKER"' \
        '  fi' \
        'fi' \
        'printf "release:%s\\n" "$1" >> "${MAINFRAME_RELEASE_TRUST_CHILD_MARKER:?}"' \
        'exit 0' > "$root/scripts/dev/release.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "${1:-}" == "--verify" ]]; then' \
        '  printf "archive:verify\\n" >> "${MAINFRAME_RELEASE_TRUST_CHILD_MARKER:?}"' \
        '  exit 0' \
        'fi' \
        'output=' \
        'while (( $# > 0 )); do' \
        '  case "$1" in --output-dir) output="$2"; shift 2 ;; *) shift ;; esac' \
        'done' \
        'mkdir -p -- "$output"' \
        'printf archive > "$output/mainframe-10.2.0.tar.gz"' \
        'printf checksum > "$output/mainframe-10.2.0.tar.gz.sha256"' \
        'printf "{}\\n" > "$output/mainframe-10.2.0.sbom.json"' \
        'printf "archive:build\\n" >> "${MAINFRAME_RELEASE_TRUST_CHILD_MARKER:?}"' \
        'exit 0' > "$root/scripts/build-release-archive.sh"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'output=' \
        'while (( $# > 0 )); do' \
        '  case "$1" in --output) output="$2"; shift 2 ;; *) shift ;; esac' \
        'done' \
        'printf "%s\\n" "class Mainframe < Formula" "end" > "$output"' \
        'printf "formula\\n" >> "${MAINFRAME_RELEASE_TRUST_CHILD_MARKER:?}"' \
        'exit 0' > "$root/scripts/dev/generate-homebrew-formula.sh"

    printf '%s\n' \
        '#!/usr/bin/env python3' \
        'raise SystemExit(0)' > "$root/scripts/dev/validate-release-sbom.py"
    printf '%s\n' \
        '#!/usr/bin/env python3' \
        'import hashlib' \
        'import json' \
        'import os' \
        'from pathlib import Path' \
        'import sys' \
        'if "--capture-source-snapshot" in sys.argv:' \
        '    target = Path(sys.argv[sys.argv.index("--capture-source-snapshot") + 1])' \
        '    root = Path(sys.argv[sys.argv.index("--source-root") + 1])' \
        '    state = hashlib.sha256((root / "VERSION").read_bytes() + (root / "package.json").read_bytes()).hexdigest()' \
        '    target.write_text(json.dumps({"state_sha256": state}, sort_keys=True) + "\\n", encoding="utf-8")' \
        '    raise SystemExit(0)' \
        'target = Path(sys.argv[sys.argv.index("--manifest") + 1])' \
        'target.write_text("candidate\\n", encoding="utf-8")' \
        'if os.environ.get("MAINFRAME_RELEASE_TRUST_MUTATE_ON_RECHECK") == "1" and "recheck" in target.parts:' \
        '    root = Path(sys.argv[sys.argv.index("--source-root") + 1])' \
        '    with (root / "package.json").open("a", encoding="utf-8") as handle: handle.write(" ")' \
        'raise SystemExit(0)' > "$root/scripts/dev/verify-release-candidate.py"
    chmod +x \
        "$root/scripts/dev/release.sh" \
        "$root/scripts/build-release-archive.sh" \
        "$root/scripts/dev/generate-homebrew-formula.sh"

    RELEASE_TRUST_ROOT="$root"
}

create_release_interpreter_sibling_fixture() {
    local root real_path
    create_release_trust_fixture
    root="$RELEASE_TRUST_ROOT"

    cp "$PROJECT_ROOT/scripts/dev/release.sh" "$root/scripts/dev/release.sh"
    cp "$PROJECT_ROOT/scripts/build-release-archive.sh" \
        "$root/scripts/build-release-archive.sh"
    cp "$PROJECT_ROOT/scripts/generate-sbom.sh" "$root/scripts/generate-sbom.sh"
    cp "$PROJECT_ROOT/scripts/dev/build-release-tar.py" \
        "$root/scripts/dev/build-release-tar.py"

    printf '%s\n' \
        'mainframe_release_payload_files() {' \
        '  printf "%s\\n" VERSION' \
        '}' \
        'mainframe_release_payload_git_pathspecs() {' \
        '  printf ":(top,literal)VERSION\\0"' \
        '}' > "$root/scripts/dev/release-payload.sh"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$root/scripts/sync-version.sh"
    chmod +x "$root/scripts/sync-version.sh"
    for real_path in \
        generate-manifest.py \
        check-owner-parity.py \
        export-gate-rules.py \
        generate-runtime-closure.py \
        check-control-plane-claim.py; do
        printf '%s\n' 'raise SystemExit(0)' > "$root/scripts/$real_path"
    done
    printf '%s\n' '#!/bin/bash -p' 'exit 0' \
        > "$root/scripts/generate-host-adapters.sh"
    chmod +x "$root/scripts/generate-host-adapters.sh"

    env -i \
        HOME="${HOME:-/tmp}" \
        TMPDIR="${TMPDIR:-/tmp}" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        "$BASH_BIN" --noprofile --norc -p \
        "$root/scripts/generate-sbom.sh" >/dev/null
}

create_sync_trust_fixture() {
    local root="$TEST_DIR/sync-trust"
    mkdir -p "$root/scripts/dev" "$root/lib" "$root/config"
    cp "$PROJECT_ROOT/scripts/sync-version.sh" "$root/scripts/sync-version.sh"
    cp "$PROJECT_ROOT/scripts/dev/release-runtime.sh" \
        "$root/scripts/dev/release-runtime.sh"
    cp "$PROJECT_ROOT/package.json" "$root/package.json"
    cp "$PROJECT_ROOT/config/pi-compatibility.json" \
        "$root/config/pi-compatibility.json"
    printf '%s\n' '10.2.0' > "$root/VERSION"
    printf '%s\n' 'readonly MAINFRAME_VERSION="10.2.0"' > "$root/lib/common.sh"
    printf '%s\n' '{}' > "$root/FUNCTIONS.json"
    printf '%s\n' \
        '#!/bin/bash -p' \
        'PROJECT_VERSION="10.2.0"' \
        'if [[ -f "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh" ]]; then' \
        '  source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"' \
        'fi' \
        'output=' \
        'while (( $# > 0 )); do' \
        '  case "$1" in --output) output="$2"; shift 2 ;; *) shift ;; esac' \
        'done' \
        'printf "{\\\"generated\\\":\\\"ignored\\\"}\\n" > "$output"' \
        > "$root/scripts/generate-functions-json.sh"
    chmod +x "$root/scripts/sync-version.sh" \
        "$root/scripts/generate-functions-json.sh"
    SYNC_TRUST_ROOT="$root"
}

teardown() {
    rm -rf -- "$TEST_DIR"
}

sha256_file() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    fi
}

create_candidate_inputs() {
    local digest

    printf 'MAINFRAME Homebrew candidate archive fixture\n' > "$ARCHIVE"
    digest="$(sha256_file "$ARCHIVE")"
    printf '%s  %s\n' "$digest" "$(basename "$ARCHIVE")" > "$CHECKSUM"
}

write_verifiable_fixture_sbom() {
    python3 - "$CANDIDATE_PAYLOAD" "$SBOM" "$PROJECT_VERSION" <<'PYEOF'
import hashlib
import json
from pathlib import Path
import sys
import uuid

payload = Path(sys.argv[1])
output = Path(sys.argv[2])
version = sys.argv[3]
names = sorted(
    (
        str(path.relative_to(payload))
        for path in payload.rglob("*")
        if path.is_file() and path.name not in {"SHA256SUMS", "sbom.json"}
    ),
    key=lambda name: name.encode("utf-8"),
)
records = []
file_components = []
for name in names:
    contents = (payload / name).read_bytes()
    digest = hashlib.sha256(contents).hexdigest()
    records.append(f"{digest}  {name}\n")
    file_components.append(
        {
            "type": "file",
            "name": name,
            "hashes": [{"alg": "SHA-256", "content": digest}],
            "properties": [{"name": "size", "value": str(len(contents))}],
        }
    )
payload_digest = hashlib.sha256("".join(records).encode("utf-8")).hexdigest()
identity = f"https://github.com/gtwatts/mainframe/sbom/{version}/{payload_digest}"
serial = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, identity)}"
document = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": serial,
    "version": 1,
    "metadata": {
        "timestamp": "1970-01-01T00:00:00Z",
        "component": {
            "type": "library",
            "bom-ref": f"mainframe@{version}",
            "name": "mainframe",
            "version": version,
        },
    },
    "components": [
        {
            "type": "application",
            "bom-ref": "runtime:bash",
            "name": "Bash",
            "version": "4.4",
            "properties": [
                {"name": "mainframe:version-constraint", "value": ">=4.4"}
            ],
        },
        {
            "type": "application",
            "bom-ref": "runtime:jq",
            "name": "jq",
            "properties": [
                {
                    "name": "mainframe:requirement",
                    "value": "required for agent enforcement and full metadata support",
                }
            ],
        },
        {
            "type": "application",
            "bom-ref": "runtime:python",
            "name": "Python",
            "version": "3.9",
            "properties": [
                {
                    "name": "mainframe:version-constraint",
                    "value": ">=3.9 for control-plane and Pi diagnosis/lifecycle",
                },
                {
                    "name": "mainframe:managed-host-version-constraint",
                    "value": ">=3.10",
                },
                {
                    "name": "mainframe:requirement",
                    "value": (
                        "durable control-plane CLI, Pi diagnosis/lifecycle, and managed-host install, remove, and restore"
                    ),
                },
            ],
        },
        *file_components,
    ],
    "dependencies": [
        {
            "ref": f"mainframe@{version}",
            "dependsOn": ["runtime:bash", "runtime:jq", "runtime:python"],
        }
    ],
}
output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
PYEOF
}

create_verifiable_candidate_inputs() {
    local source

    CANDIDATE_PAYLOAD="$TEST_DIR/payload"
    mkdir -p "$CANDIDATE_PAYLOAD"
    for source in \
        VERSION \
        FUNCTIONS.json \
        MANIFEST.json \
        INVOCATION_INDEX.json \
        bin/mainframe \
        get-mainframe.sh \
        install.sh \
        scripts/upgrade-release.sh \
        hooks/agent-gateway.sh \
        lib/agent_safety.sh \
        lib/launch.sh \
        security/gate-rules.json \
        security/gate-normalizer.mjs; do
        mkdir -p "$CANDIDATE_PAYLOAD/$(dirname "$source")"
        cp -p "$PROJECT_ROOT/$source" "$CANDIDATE_PAYLOAD/$source"
    done
    write_verifiable_fixture_sbom
    cp "$SBOM" "$CANDIDATE_PAYLOAD/sbom.json"
    package_verifiable_candidate_inputs
}

package_verifiable_candidate_inputs() {
    local file digest
    local -a files

    mapfile -t files < <(
        cd "$CANDIDATE_PAYLOAD"
        find . -type f ! -name SHA256SUMS -print \
            | sed 's#^\./##' \
            | LC_ALL=C sort
    )
    : > "$CANDIDATE_PAYLOAD/SHA256SUMS"
    for file in "${files[@]}"; do
        digest="$(sha256_file "$CANDIDATE_PAYLOAD/$file")"
        printf '%s  %s\n' "$digest" "$file" \
            >> "$CANDIDATE_PAYLOAD/SHA256SUMS"
    done
    files+=(SHA256SUMS)
    (
        cd "$CANDIDATE_PAYLOAD"
        COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" "${files[@]}"
    )
    digest="$(sha256_file "$ARCHIVE")"
    printf '%s  %s\n' "$digest" "$(basename "$ARCHIVE")" > "$CHECKSUM"
    "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$FORMULA" >/dev/null
}

run_generator() {
    run "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$FORMULA"
}

create_source_provenance_fixture() {
    SYSTEM_GIT=/usr/bin/git
    [[ -x "$SYSTEM_GIT" && ! -L "$SYSTEM_GIT" ]] || \
        skip "fixed system Git is unavailable"
    SOURCE_ROOT="$TEST_DIR/source-root"
    SOURCE_INVENTORY="$TEST_DIR/source-inventory"
    SOURCE_PATHSPECS="$TEST_DIR/source-pathspecs"
    SOURCE_SNAPSHOT="$TEST_DIR/source-snapshot.json"
    mkdir -p "$SOURCE_ROOT/payload"
    printf 'base\n' > "$SOURCE_ROOT/payload/a.txt"
    printf 'payload/a.txt\n' > "$SOURCE_INVENTORY"
    printf ':(top,literal)payload\0' > "$SOURCE_PATHSPECS"
    "$SYSTEM_GIT" -C "$SOURCE_ROOT" init -q
    "$SYSTEM_GIT" -C "$SOURCE_ROOT" add -- payload/a.txt
    "$SYSTEM_GIT" -C "$SOURCE_ROOT" \
        -c user.name=Mainframe \
        -c user.email=mainframe@example.invalid \
        commit -qm base
}

capture_source_provenance() {
    run "$PYTHON_BIN" -I -S -B "$CANDIDATE_VERIFIER" \
        --source-root "$SOURCE_ROOT" \
        --source-inventory "$SOURCE_INVENTORY" \
        --source-pathspecs "$SOURCE_PATHSPECS" \
        --capture-source-snapshot "$SOURCE_SNAPSHOT"
}

source_path_set_digest() {
    "$PYTHON_BIN" -I -S -B - "$@" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
digest.update(b"MAINFRAME-RELEASE-PAYLOAD-CHANGE-PATH-SET-SHA256-V1\0")
for name in sorted(sys.argv[1:], key=lambda value: value.encode("utf-8")):
    digest.update(name.encode("utf-8"))
    digest.update(b"\0")
print(digest.hexdigest())
PY
}

@test "source provenance captures a clean payload without disclosing paths" {
    local base_commit empty_digest fake_bin marker object_format
    create_source_provenance_fixture
    base_commit="$("$SYSTEM_GIT" -C "$SOURCE_ROOT" rev-parse HEAD)"
    object_format="$("$SYSTEM_GIT" -C "$SOURCE_ROOT" rev-parse --show-object-format)"
    empty_digest="$(source_path_set_digest)"
    fake_bin="$TEST_DIR/fake-bin"
    marker="$TEST_DIR/path-git-ran"
    mkdir "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf poisoned > "$MAINFRAME_PROVENANCE_GIT_MARKER"' \
        'exit 97' > "$fake_bin/git"
    chmod +x "$fake_bin/git"

    run env \
        PATH="$fake_bin:$PATH" \
        GIT_DIR="$TEST_DIR/poison-git-dir" \
        GIT_WORK_TREE="$TEST_DIR/poison-work-tree" \
        MAINFRAME_PROVENANCE_GIT_MARKER="$marker" \
        "$PYTHON_BIN" -I -S -B "$CANDIDATE_VERIFIER" \
        --source-root "$SOURCE_ROOT" \
        --source-inventory "$SOURCE_INVENTORY" \
        --source-pathspecs "$SOURCE_PATHSPECS" \
        --capture-source-snapshot "$SOURCE_SNAPSHOT"

    [[ "$status" -eq 0 ]]
    [[ ! -e "$marker" ]]
    jq -e \
      --arg commit "$base_commit" \
      --arg digest "$empty_digest" \
      --arg object_format "$object_format" '
      (.source | keys) == [
        "availability", "base_commit", "change_path_set_sha256",
        "clean_checkout_reproducible", "format", "object_format",
        "path_disclosure", "release_root_state", "scope",
        "tracked_change_path_count", "untracked_payload_file_count"
      ] and
      .source == {
        format: "mainframe-release-source-provenance-v1",
        availability: true,
        base_commit: $commit,
        object_format: $object_format,
        scope: "canonical-release-payload-v1",
        release_root_state: "clean",
        clean_checkout_reproducible: true,
        tracked_change_path_count: 0,
        untracked_payload_file_count: 0,
        change_path_set_sha256: $digest,
        path_disclosure: "digest-only"
      }
    ' "$SOURCE_SNAPSHOT" >/dev/null
    ! grep -Fq 'payload/a.txt' "$SOURCE_SNAPSHOT"
    ! grep -Fq 'mainframe@example.invalid' "$SOURCE_SNAPSHOT"
}

@test "source provenance accepts and aggregates a dirty tracked payload" {
    local expected_digest
    create_source_provenance_fixture
    printf 'dirty\n' >> "$SOURCE_ROOT/payload/a.txt"
    expected_digest="$(source_path_set_digest payload/a.txt)"

    capture_source_provenance

    [[ "$status" -eq 0 ]]
    jq -e --arg digest "$expected_digest" '
      .source.availability == true and
      .source.release_root_state == "dirty" and
      .source.clean_checkout_reproducible == false and
      .source.tracked_change_path_count == 1 and
      .source.untracked_payload_file_count == 0 and
      .source.change_path_set_sha256 == $digest
    ' "$SOURCE_SNAPSHOT" >/dev/null
    ! grep -Fq 'payload/a.txt' "$SOURCE_SNAPSHOT"
}

@test "source provenance counts an untracked payload file without naming it" {
    local expected_digest
    create_source_provenance_fixture
    printf 'new\n' > "$SOURCE_ROOT/payload/new.txt"
    printf '%s\n' payload/a.txt payload/new.txt > "$SOURCE_INVENTORY"
    expected_digest="$(source_path_set_digest payload/new.txt)"

    capture_source_provenance

    [[ "$status" -eq 0 ]]
    jq -e --arg digest "$expected_digest" '
      .source.availability == true and
      .source.release_root_state == "dirty" and
      .source.clean_checkout_reproducible == false and
      .source.tracked_change_path_count == 0 and
      .source.untracked_payload_file_count == 1 and
      .source.change_path_set_sha256 == $digest
    ' "$SOURCE_SNAPSHOT" >/dev/null
    ! grep -Fq 'payload/new.txt' "$SOURCE_SNAPSHOT"
}

@test "source provenance keeps a non-Git payload valid with closed null fields" {
    SOURCE_ROOT="$TEST_DIR/non-git-source"
    SOURCE_INVENTORY="$TEST_DIR/non-git-inventory"
    SOURCE_PATHSPECS="$TEST_DIR/non-git-pathspecs"
    SOURCE_SNAPSHOT="$TEST_DIR/non-git-snapshot.json"
    mkdir -p "$SOURCE_ROOT/payload"
    printf 'local\n' > "$SOURCE_ROOT/payload/a.txt"
    printf 'payload/a.txt\n' > "$SOURCE_INVENTORY"
    printf ':(top,literal)payload\0' > "$SOURCE_PATHSPECS"

    capture_source_provenance

    [[ "$status" -eq 0 ]]
    jq -e '
      .source == {
        format: "mainframe-release-source-provenance-v1",
        availability: false,
        base_commit: null,
        object_format: null,
        scope: "canonical-release-payload-v1",
        release_root_state: "unavailable",
        clean_checkout_reproducible: false,
        tracked_change_path_count: null,
        untracked_payload_file_count: null,
        change_path_set_sha256: null,
        path_disclosure: "digest-only"
      }
    ' "$SOURCE_SNAPSHOT" >/dev/null
}

@test "private source state detects index drift hidden by equal public aggregates" {
    local first_snapshot second_snapshot
    create_source_provenance_fixture
    first_snapshot="$TEST_DIR/first-source-snapshot.json"
    second_snapshot="$TEST_DIR/second-source-snapshot.json"
    printf 'staged-one\n' > "$SOURCE_ROOT/payload/a.txt"
    "$SYSTEM_GIT" -C "$SOURCE_ROOT" add -- payload/a.txt
    printf 'same-working-tree\n' > "$SOURCE_ROOT/payload/a.txt"
    SOURCE_SNAPSHOT="$first_snapshot"
    capture_source_provenance
    [[ "$status" -eq 0 ]]

    printf 'staged-two\n' > "$SOURCE_ROOT/payload/a.txt"
    "$SYSTEM_GIT" -C "$SOURCE_ROOT" add -- payload/a.txt
    printf 'same-working-tree\n' > "$SOURCE_ROOT/payload/a.txt"
    SOURCE_SNAPSHOT="$second_snapshot"
    capture_source_provenance
    [[ "$status" -eq 0 ]]

    jq -S '.source' "$first_snapshot" > "$TEST_DIR/first-public-source.json"
    jq -S '.source' "$second_snapshot" > "$TEST_DIR/second-public-source.json"
    cmp -s "$TEST_DIR/first-public-source.json" "$TEST_DIR/second-public-source.json"
    [[ "$(jq -r '.state_sha256' "$first_snapshot")" != \
       "$(jq -r '.state_sha256' "$second_snapshot")" ]]
}

@test "generator renders a deterministic tap-ready formula for the exact archive" {
    local digest second_formula
    create_candidate_inputs
    digest="$(sha256_file "$ARCHIVE")"
    second_formula="$TEST_DIR/mainframe-second.rb"

    run_generator

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Generated unpublished Homebrew candidate"* ]]
    [[ -f "$FORMULA" ]]
    grep -Fq "class Mainframe < Formula" "$FORMULA"
    grep -Fq "releases/download/v${PROJECT_VERSION}/mainframe-${PROJECT_VERSION}.tar.gz" "$FORMULA"
    grep -Fq "sha256 \"$digest\"" "$FORMULA"
    grep -Fq 'depends_on "bash"' "$FORMULA"
    grep -Fq 'depends_on "jq"' "$FORMULA"
    grep -Fq 'depends_on "python@3.14"' "$FORMULA"
    grep -Fq 'formula_opt_bin("bash")' "$FORMULA"
    grep -Fq 'formula_opt_bin("jq")' "$FORMULA"
    grep -Fq 'libexec.find do |path|' "$FORMULA"
    grep -Fq 'path.chmod 0755 if path.directory? && !path.symlink?' "$FORMULA"
    grep -Fq 'cp libexec/"LICENSE", prefix/"LICENSE"' "$FORMULA"
    grep -Fq 'assert_path_exists libexec/"README.md"' "$FORMULA"
    grep -Fq 'assert_equal 0, path.stat.mode & 07022, path.to_s' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_INSTALL_METHOD:[[:space:]]+"homebrew",$' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_HOMEBREW_BASH_OPT_BIN:[[:space:]]+formula_opt_bin\("bash"\)\.to_s,$' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_HOMEBREW_JQ_OPT_BIN:[[:space:]]+formula_opt_bin\("jq"\)\.to_s,$' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_HOMEBREW_OPT_BIN:[[:space:]]+opt_bin\.to_s,$' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_HOMEBREW_OPT_LIBEXEC:[[:space:]]+opt_libexec\.to_s,$' "$FORMULA"
    grep -Eq '^[[:space:]]*MAINFRAME_PI_LIFECYCLE_REQUIRED:[[:space:]]+"1",$' "$FORMULA"
    grep -Fq 'opt_libexec' "$FORMULA"
    grep -Fq '#{opt_bin}/mainframe setup --project .' "$FORMULA"
    grep -Fq '#{opt_bin}/mainframe pi doctor' "$FORMULA"
    grep -Fq 'Mode: discovery only (strictly read-only)' "$FORMULA"
    grep -Fq 'MAINFRAME_PI_DOCTOR_EXIT=%s' "$FORMULA"
    grep -Fq 'assert_equal "MAINFRAME_PI_DOCTOR_EXIT=2\n"' "$FORMULA"
    grep -Fq '"executed":false' "$FORMULA"
    grep -Fq '#{opt_bin}/mainframe deactivate HOST --project . --enforce' "$FORMULA"
    grep -Fq '#{opt_bin}/mainframe pi remove --dry-run' "$FORMULA"
    grep -Fq '#{opt_bin}/mainframe pi remove --yes' "$FORMULA"
    grep -Fq 'brew uninstall gtwatts/mainframe/mainframe' "$FORMULA"
    grep -Fq 'Formulae do not provide an uninstall-preflight hook' "$FORMULA"
    grep -Fq 'project hook or leave the Pi package path dangling' "$FORMULA"
    grep -Fq 'mainframe awm init homebrew-formula' "$FORMULA"
    grep -Fq 'terraform-destroy' "$FORMULA"
    grep -Fq 'mainframe protect status gemini' "$FORMULA"
    grep -Fq 'Static readiness: READY' "$FORMULA"
    ! grep -Eq '@[A-Z][A-Z0-9_]*@' "$FORMULA"

    run "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$second_formula"
    [[ "$status" -eq 0 ]]
    cmp -s "$FORMULA" "$second_formula"

    if command -v ruby >/dev/null 2>&1; then
        run ruby -c "$FORMULA"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"Syntax OK"* ]]
    fi
}

@test "generator canonicalizes output and cannot replace inputs or directories" {
    local archive_before case_variant output_directory linked_parent real_parent
    create_candidate_inputs
    archive_before="$(sha256_file "$ARCHIVE")"

    run "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$TEST_DIR/./$(basename "$ARCHIVE")"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output must not overwrite an input"* ]]
    [[ "$(sha256_file "$ARCHIVE")" == "$archive_before" ]]

    case_variant="$TEST_DIR/MAINFRAME-${PROJECT_VERSION}.TAR.GZ"
    if [[ "$case_variant" -ef "$ARCHIVE" ]]; then
        run "$BASH_BIN" "$GENERATOR" \
            --archive "$ARCHIVE" \
            --checksum "$CHECKSUM" \
            --output "$case_variant"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *"output must not overwrite an input"* ]]
        [[ "$(sha256_file "$ARCHIVE")" == "$archive_before" ]]
    fi

    output_directory="$TEST_DIR/existing-output"
    mkdir "$output_directory"
    run "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$output_directory"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output must be absent or a regular file"* ]]
    [[ -z "$(find "$output_directory" -mindepth 1 -print -quit)" ]]

    real_parent="$TEST_DIR/real-parent"
    linked_parent="$TEST_DIR/linked-parent"
    mkdir "$real_parent"
    ln -s "$real_parent" "$linked_parent"
    run "$BASH_BIN" "$GENERATOR" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --output "$linked_parent/mainframe.rb"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"output parent must be an existing, non-symlink directory"* ]]
    [[ ! -e "$real_parent/mainframe.rb" ]]
}

@test "generator rejects a checksum for a different asset" {
    create_candidate_inputs
    digest="$(sha256_file "$ARCHIVE")"
    printf '%s  other.tar.gz\n' "$digest" > "$CHECKSUM"

    run_generator

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"does not name the exact asset"* ]]
    [[ ! -e "$FORMULA" ]]
}

@test "generator rejects multiple checksum records" {
    local checksum_record
    create_candidate_inputs
    checksum_record="$(cat "$CHECKSUM")"
    printf '%s\n' "$checksum_record" >> "$CHECKSUM"

    run_generator

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"exactly one record"* ]]
    [[ ! -e "$FORMULA" ]]
}

@test "generator detects archive tampering and preserves an existing output" {
    create_candidate_inputs
    printf 'do not replace\n' > "$FORMULA"
    printf 'tampered\n' >> "$ARCHIVE"

    run_generator

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive digest does not match"* ]]
    [[ "$(cat "$FORMULA")" == "do not replace" ]]
}

@test "candidate verifier emits deterministic hashes and rejects a stale formula" {
    local manifest="$TEST_DIR/mainframe-${PROJECT_VERSION}.candidate.json"
    local second_dir="$TEST_DIR/second"
    local stale_dir="$TEST_DIR/stale"
    local second_manifest stale_manifest archive_digest

    create_verifiable_candidate_inputs
    mkdir -p "$second_dir" "$stale_dir"
    second_manifest="$second_dir/mainframe-${PROJECT_VERSION}.candidate.json"
    stale_manifest="$stale_dir/mainframe-${PROJECT_VERSION}.candidate.json"

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$manifest"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"release candidate valid"* ]]
    archive_digest="$(sha256_file "$ARCHIVE")"
    jq -e \
        --arg version "$PROJECT_VERSION" \
        --arg archive "$archive_digest" '
          .schema ==
            "https://github.com/gtwatts/mainframe/schemas/release-candidate/v2" and
          (keys | sort) == ["artifacts", "schema", "source", "version"] and
          .version == $version and
          .artifacts.archive == {
            name: ("mainframe-" + $version + ".tar.gz"),
            sha256: $archive
          } and
          (.artifacts | keys) == ["archive", "checksum", "formula", "sbom"] and
          ([.artifacts[].sha256 | test("^[0-9a-f]{64}$")] | all) and
          .source == {
            format: "mainframe-release-source-provenance-v1",
            availability: false,
            base_commit: null,
            object_format: null,
            scope: "canonical-release-payload-v1",
            release_root_state: "unavailable",
            clean_checkout_reproducible: false,
            tracked_change_path_count: null,
            untracked_payload_file_count: null,
            change_path_set_sha256: null,
            path_disclosure: "digest-only"
          }
        ' "$manifest" >/dev/null

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$second_manifest"
    [[ "$status" -eq 0 ]]
    cmp -s "$manifest" "$second_manifest"

    # Rebuilding or changing an archive after formula generation must make the
    # old formula unusable even when the checksum sidecar follows the new bytes.
    cp "$FORMULA" "$stale_dir/mainframe.rb"
    printf 'later archive bytes\n' >> "$ARCHIVE"
    archive_digest="$(sha256_file "$ARCHIVE")"
    printf '%s  %s\n' "$archive_digest" "$(basename "$ARCHIVE")" > "$CHECKSUM"
    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$stale_dir/mainframe.rb" \
        --manifest "$stale_manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"formula SHA-256 does not match the candidate archive"* ]]
    [[ ! -e "$stale_manifest" ]]
}

@test "candidate verifier requires the critical installed and safety payload" {
    local incomplete_dir="$TEST_DIR/incomplete"
    local incomplete_manifest

    create_verifiable_candidate_inputs
    rm "$CANDIDATE_PAYLOAD/bin/mainframe"
    package_verifiable_candidate_inputs
    mkdir -p "$incomplete_dir"
    incomplete_manifest="$incomplete_dir/mainframe-${PROJECT_VERSION}.candidate.json"

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$incomplete_manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive is missing required members: bin/mainframe"* ]]
    [[ ! -e "$incomplete_manifest" ]]
}

@test "candidate verifier rejects an SBOM that passes shallow product identity" {
    local malformed="$TEST_DIR/malformed-sbom.json"
    local manifest="$TEST_DIR/mainframe-${PROJECT_VERSION}.candidate.json"

    create_verifiable_candidate_inputs
    jq '.specVersion = "1.4"' "$SBOM" > "$malformed"
    mv "$malformed" "$SBOM"
    cp "$SBOM" "$CANDIDATE_PAYLOAD/sbom.json"
    package_verifiable_candidate_inputs

    # This is the old verifier's complete product-identity check. The fixture
    # deliberately passes it while violating the attestation SBOM contract.
    jq -e --arg version "$PROJECT_VERSION" '
      .bomFormat == "CycloneDX" and
      .metadata.component.name == "mainframe" and
      .metadata.component.version == $version and
      .specVersion == "1.4"
    ' "$SBOM" >/dev/null

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"strong SBOM validation failed"* ]]
    [[ "$output" == *"specVersion must be 1.5"* ]]
    [[ ! -e "$manifest" ]]
}

@test "candidate verifier rejects an invented SBOM file component" {
    local forged="$TEST_DIR/forged-sbom.json"
    local manifest="$TEST_DIR/mainframe-${PROJECT_VERSION}.candidate.json"

    create_verifiable_candidate_inputs
    jq '(.components[] | select(.type == "file" and .name == "VERSION") | .name) = "invented.txt"' \
        "$SBOM" > "$forged"
    mv "$forged" "$SBOM"
    cp "$SBOM" "$CANDIDATE_PAYLOAD/sbom.json"
    package_verifiable_candidate_inputs

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"SBOM file inventory does not match archive payload"* ]]
    [[ "$output" == *"invented: invented.txt"* ]]
    [[ ! -e "$manifest" ]]
}

@test "candidate verifier rejects a forged SBOM file hash" {
    local forged="$TEST_DIR/forged-sbom.json"
    local manifest="$TEST_DIR/mainframe-${PROJECT_VERSION}.candidate.json"

    create_verifiable_candidate_inputs
    jq '(.components[] | select(.type == "file" and .name == "VERSION") | .hashes[0].content) = "0000000000000000000000000000000000000000000000000000000000000000"' \
        "$SBOM" > "$forged"
    mv "$forged" "$SBOM"
    cp "$SBOM" "$CANDIDATE_PAYLOAD/sbom.json"
    package_verifiable_candidate_inputs

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"SBOM SHA-256 does not match archive member: VERSION"* ]]
    [[ ! -e "$manifest" ]]
}

@test "candidate verifier rejects a canonical but invented UUIDv5 serial" {
    local forged="$TEST_DIR/forged-sbom.json"
    local manifest="$TEST_DIR/mainframe-${PROJECT_VERSION}.candidate.json"
    local forged_serial

    create_verifiable_candidate_inputs
    forged_serial="$(python3 -c 'import uuid; print("urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "forged")))')"
    jq --arg serial "$forged_serial" '.serialNumber = $serial' "$SBOM" > "$forged"
    mv "$forged" "$SBOM"
    cp "$SBOM" "$CANDIDATE_PAYLOAD/sbom.json"
    package_verifiable_candidate_inputs

    run python3 "$CANDIDATE_VERIFIER" \
        --version "$PROJECT_VERSION" \
        --archive "$ARCHIVE" \
        --checksum "$CHECKSUM" \
        --sbom "$SBOM" \
        --formula "$FORMULA" \
        --manifest "$manifest"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"SBOM serialNumber does not match the generator identity"* ]]
    [[ ! -e "$manifest" ]]
}

@test "candidate builder composes existing gates and keeps check mode read-only" {
    run "$BASH_BIN" -n "$CANDIDATE_BUILDER"
    [[ "$status" -eq 0 ]]

    grep -F 'release.sh" --prepare' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'release.sh" --check' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'build-release-archive.sh" --verify' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'build-release-archive.sh" --output-dir "$expected"' \
        "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'generate-homebrew-formula.sh"' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'verify-release-candidate.py"' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'release-candidate: ##' "$PROJECT_ROOT/Makefile" >/dev/null
    grep -F 'no package was assembled or published' "$PROJECT_ROOT/Makefile" >/dev/null

    # Release metadata must be current before the build gate, while candidate
    # assembly must happen only after that gate succeeds.
    run awk '
      /^release-candidate:/ {
        in_target=1
        if ($0 ~ /^release-candidate: build/) exit 2
        next
      }
      in_target && /release\.sh --prepare/ {
        if (step != 0) exit 3
        step=1
        next
      }
      in_target && /\$\(MAKE\) build/ {
        if (step != 1) exit 4
        step=2
        next
      }
      in_target && /release-candidate\.sh --prepare/ {
        if (step != 2) exit 5
        step=3
        next
      }
      in_target && /^$/ { exit step == 3 ? 0 : 6 }
      END { if (!in_target || step != 3) exit 7 }
    ' "$PROJECT_ROOT/Makefile"
    [[ "$status" -eq 0 ]]

    # The check branch compares expected/actual bytes and writes verifier output
    # only below its private scratch directory, never into the requested output.
    run awk '
      /if \[\[ "\$mode" == "check" \]\]; then/ { in_check=1 }
      in_check { print }
      in_check && /exit 0/ { exit }
    ' "$CANDIDATE_BUILDER"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'cmp -s -- "$expected/$name" "$target"'* ]]
    [[ "$output" == *'actual_manifest="$recheck/$manifest_name"'* ]]
    [[ "$output" != *'mv -f --'* ]]
    [[ "$output" != *'rm -f --'* ]]

    grep -F 'lock_root="${TMPDIR:-/tmp}/mainframe-release-candidate-locks-$(id -u)"' \
        "$CANDIDATE_BUILDER" >/dev/null
    grep -F '[[ -d "$lock_root" && ! -L "$lock_root" && -O "$lock_root" ]]' \
        "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'trap handle_int INT' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'trap handle_term TERM' "$CANDIDATE_BUILDER" >/dev/null
    grep -F 'export PYTHONDONTWRITEBYTECODE=1' "$CANDIDATE_BUILDER" >/dev/null
    grep -F '"$MAINFRAME_RELEASE_BASH" --noprofile --norc -p' \
        "$CANDIDATE_BUILDER" >/dev/null
    ! grep -E '^"\$ROOT_DIR/.+\.sh"' "$CANDIDATE_BUILDER" >/dev/null
}

@test "candidate builder rolls back when final payload or index provenance drifts" {
    local child_marker name
    local -a candidate_names=(
        mainframe-10.2.0.tar.gz
        mainframe-10.2.0.tar.gz.sha256
        mainframe-10.2.0.sbom.json
        mainframe.rb
        mainframe-10.2.0.candidate.json
    )
    create_release_trust_fixture
    child_marker="$TEST_DIR/release-child-ran"
    for name in "${candidate_names[@]}"; do
        printf 'old-%s\n' "$name" > "$RELEASE_TRUST_ROOT/output/$name"
    done

    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_MUTATE_ON_RECHECK=1 \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --prepare --output-dir "$RELEASE_TRUST_ROOT/output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"release source or Git index changed during candidate assembly"* ]]
    for name in "${candidate_names[@]}"; do
        [[ "$(< "$RELEASE_TRUST_ROOT/output/$name")" == "old-$name" ]]
    done
}

@test "candidate check rejects shell startup, exported function, and PATH Bash injection" {
    local child_marker poison poison_marker function_marker fake_bin fake_marker
    create_release_trust_fixture
    child_marker="$TEST_DIR/release-child-ran"
    poison="$TEST_DIR/poison-bash-env.sh"
    poison_marker="$TEST_DIR/bash-env-ran"
    function_marker="$TEST_DIR/exported-function-ran"
    fake_bin="$TEST_DIR/fake-bin"
    fake_marker="$TEST_DIR/path-bash-ran"

    printf '%s\n' \
        'printf poisoned > "$MAINFRAME_RELEASE_TRUST_POISON_MARKER"' \
        'return 0 2>/dev/null || true' > "$poison"
    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_POISON_MARKER="$poison_marker" \
        BASH_ENV="$poison" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ -s "$child_marker" ]]
    [[ ! -e "$poison_marker" ]]

    mkdir() {
        printf poisoned > "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"
        /bin/mkdir "$@"
    }
    export -f mkdir
    : > "$child_marker"
    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER="$function_marker" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"
    unset -f mkdir
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ -s "$child_marker" ]]
    [[ ! -e "$function_marker" ]]

    /bin/mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf poisoned > "$MAINFRAME_RELEASE_TRUST_FAKE_BASH_MARKER"' \
        'exec "$MAINFRAME_RELEASE_TRUST_REAL_BASH" "$@"' > "$fake_bin/bash"
    chmod +x "$fake_bin/bash"

    run env \
        PATH="$fake_bin:$PATH" \
        MAINFRAME_BASH=bash \
        MAINFRAME_RELEASE_TRUST_FAKE_BASH_MARKER="$fake_marker" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"MAINFRAME_BASH must be an absolute path"* ]]
    [[ ! -e "$fake_marker" ]]

    : > "$child_marker"
    run env \
        PATH="$fake_bin:$PATH" \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_FAKE_BASH_MARKER="$fake_marker" \
        MAINFRAME_RELEASE_TRUST_REAL_BASH="$BASH_BIN" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ -s "$child_marker" ]]
    [[ ! -e "$fake_marker" ]]
}

@test "reviewed custom Python does not trust sibling tr or python3 executables" {
    local runtime_dir reviewed_python tr_marker python_marker child_marker
    create_release_interpreter_sibling_fixture
    runtime_dir="$TEST_DIR/reviewed-python-runtime"
    reviewed_python="$runtime_dir/reviewed-python"
    tr_marker="$TEST_DIR/sibling-tr-ran"
    python_marker="$TEST_DIR/sibling-python3-ran"
    child_marker="$TEST_DIR/release-child-ran"
    mkdir -p "$runtime_dir"

    printf '%s\n' \
        '#!/bin/sh' \
        'exec "$MAINFRAME_RELEASE_TRUST_REAL_PYTHON" "$@"' \
        > "$reviewed_python"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf poisoned > "$MAINFRAME_RELEASE_TRUST_TR_MARKER"' \
        'exec "$MAINFRAME_RELEASE_TRUST_REAL_TR" "$@"' \
        > "$runtime_dir/tr"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf poisoned > "$MAINFRAME_RELEASE_TRUST_PYTHON_MARKER"' \
        'exec "$MAINFRAME_RELEASE_TRUST_REAL_PYTHON" "$@"' \
        > "$runtime_dir/python3"
    chmod +x "$reviewed_python" "$runtime_dir/tr" "$runtime_dir/python3"

    run env \
        PATH="$runtime_dir:$PATH" \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$reviewed_python" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_REAL_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_REAL_TR="$(command -v tr)" \
        MAINFRAME_RELEASE_TRUST_TR_MARKER="$tr_marker" \
        MAINFRAME_RELEASE_TRUST_PYTHON_MARKER="$python_marker" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ ! -e "$tr_marker" ]]
    [[ ! -e "$python_marker" ]]
}

@test "release descendants do not inherit loader hooks or test-only path overrides" {
    local child_marker env_marker
    create_release_trust_fixture
    child_marker="$TEST_DIR/release-child-ran"
    env_marker="$TEST_DIR/release-loader-env-leaked"

    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_ENV_MARKER="$env_marker" \
        MAINFRAME_ROOT="$TEST_DIR/alternate-mainframe-root" \
        MAINFRAME_MANIFEST_PATH="$TEST_DIR/alternate-manifest.json" \
        MAINFRAME_INVOCATION_INDEX_PATH="$TEST_DIR/alternate-invocation-index.json" \
        MAINFRAME_LSP_META_PATH="$TEST_DIR/alternate-lsp.json" \
        BASHOPTS=checkwinsize \
        SHELLOPTS=braceexpand \
        PERL5OPT=-Mstrict \
        PERL5LIB="$TEST_DIR" \
        PERLLIB="$TEST_DIR" \
        RUBYOPT=-w \
        RUBYLIB="$TEST_DIR" \
        NODE_OPTIONS=--no-warnings \
        NODE_PATH="$TEST_DIR" \
        NODE_REDIRECT_WARNINGS="$TEST_DIR/node-warnings" \
        NODE_REPL_HISTORY="$TEST_DIR/node-repl-history" \
        NODE_V8_COVERAGE="$TEST_DIR/node-v8-coverage" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ -s "$child_marker" ]]
    [[ ! -e "$env_marker" ]]
}

@test "explicit Bash invocation reenters before inherited cd set or builtin functions" {
    local ambient_marker ambient_root child_marker function_marker
    create_release_trust_fixture
    create_sync_trust_fixture
    ambient_root="$TEST_DIR/ambient-mainframe"
    ambient_marker="$TEST_DIR/ambient-mainframe-ran"
    child_marker="$TEST_DIR/release-child-ran"
    function_marker="$TEST_DIR/inherited-cd-ran"
    mkdir -p "$ambient_root/lib"
    printf '%s\n' \
        'printf poisoned > "$MAINFRAME_RELEASE_TRUST_AMBIENT_ROOT_MARKER"' \
        > "$ambient_root/lib/common.sh"

    run env \
        'BASH_FUNC_cd%%=() { printf "cd\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin cd "$@"; }' \
        'BASH_FUNC_set%%=() { printf "set\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin set "$@"; }' \
        'BASH_FUNC_builtin%%=() { printf "builtin\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin "$@"; }' \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_CHILD_MARKER="$child_marker" \
        MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER="$function_marker" \
        "$BASH_BIN" "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"candidate output is missing or unsafe"* ]]
    [[ -s "$child_marker" ]]
    [[ ! -e "$function_marker" ]]

    run env \
        'BASH_FUNC_cd%%=() { printf "cd\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin cd "$@"; }' \
        'BASH_FUNC_set%%=() { printf "set\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin set "$@"; }' \
        'BASH_FUNC_builtin%%=() { printf "builtin\\n" >> "$MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER"; command builtin "$@"; }' \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_ROOT="$ambient_root" \
        MAINFRAME_RELEASE_TRUST_AMBIENT_ROOT_MARKER="$ambient_marker" \
        MAINFRAME_RELEASE_TRUST_FUNCTION_MARKER="$function_marker" \
        "$BASH_BIN" "$SYNC_TRUST_ROOT/scripts/sync-version.sh" --check

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"MAINFRAME version source of truth:"* ]]
    [[ ! -e "$ambient_marker" ]]
    [[ ! -e "$function_marker" ]]
}

@test "sync check preserves pre-existing backup files" {
    create_sync_trust_fixture
    printf 'common backup sentinel\n' > "$SYNC_TRUST_ROOT/lib/common.sh.bak"
    printf 'generator backup sentinel\n' \
        > "$SYNC_TRUST_ROOT/scripts/generate-functions-json.sh.bak"

    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        "$SYNC_TRUST_ROOT/scripts/sync-version.sh" --check

    [[ "$status" -eq 0 ]]
    [[ "$(< "$SYNC_TRUST_ROOT/lib/common.sh.bak")" == \
       "common backup sentinel" ]]
    [[ "$(< "$SYNC_TRUST_ROOT/scripts/generate-functions-json.sh.bak")" == \
       "generator backup sentinel" ]]
}

@test "release Python ignores modules in the caller working directory" {
    local hostile_cwd marker original_cwd
    create_release_trust_fixture
    hostile_cwd="$TEST_DIR/hostile-python-cwd"
    marker="$TEST_DIR/hostile-python-imported"
    mkdir -p "$hostile_cwd"
    cat > "$hostile_cwd/hashlib.py" <<'PY'
import os
from pathlib import Path

Path(os.environ["MAINFRAME_RELEASE_TRUST_PYTHON_IMPORT_MARKER"]).write_text(
    "imported\n", encoding="ascii"
)
raise RuntimeError("hostile cwd hashlib imported")
PY
    original_cwd="$PWD"
    cd "$hostile_cwd"

    run env \
        MAINFRAME_BASH="$BASH_BIN" \
        MAINFRAME_PYTHON="$PYTHON_BIN" \
        MAINFRAME_RELEASE_TRUST_PYTHON_IMPORT_MARKER="$marker" \
        "$RELEASE_TRUST_ROOT/scripts/dev/release-candidate.sh" \
        --check --output-dir "$RELEASE_TRUST_ROOT/output"
    cd "$original_cwd"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$marker" ]]
}

@test "generator refuses symbolic-link archive and output paths" {
    local real_archive real_output
    create_candidate_inputs
    real_archive="$TEST_DIR/real-archive"
    mv "$ARCHIVE" "$real_archive"
    ln -s "$real_archive" "$ARCHIVE"

    run_generator

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"archive must be a regular, non-symlink file"* ]]

    rm "$ARCHIVE"
    mv "$real_archive" "$ARCHIVE"
    real_output="$TEST_DIR/real-output"
    printf 'sentinel\n' > "$real_output"
    ln -s "$real_output" "$FORMULA"

    run_generator

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to replace symbolic-link output"* ]]
    [[ "$(cat "$real_output")" == "sentinel" ]]
}

@test "Homebrew install method returns package-manager upgrade guidance" {
    mkdir -p "$TEST_DIR/home" "$TEST_DIR/awm"

    run env \
        HOME="$TEST_DIR/home" \
        AWM_ROOT="$TEST_DIR/awm" \
        MAINFRAME_INSTALL_METHOD=homebrew \
        "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" update

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"MAINFRAME is managed by Homebrew"* ]]
    [[ "$output" == *"brew upgrade gtwatts/mainframe/mainframe"* ]]
    [[ "$output" != *"basher upgrade"* ]]

    run env \
        HOME="$TEST_DIR/home" \
        AWM_ROOT="$TEST_DIR/awm" \
        MAINFRAME_INSTALL_METHOD=homebrew \
        "$BASH_BIN" "$PROJECT_ROOT/bin/mainframe" upgrade --version 10.3.0

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"MAINFRAME is managed by Homebrew"* ]]
    [[ "$output" == *"brew upgrade gtwatts/mainframe/mainframe"* ]]
}

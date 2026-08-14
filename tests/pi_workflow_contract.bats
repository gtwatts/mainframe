#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
}

@test "Pi workflow binds exact packages, native platforms, candidate archive, and release gate" {
    run python3 - \
        "$PROJECT_ROOT/config/pi-compatibility.json" \
        "$PROJECT_ROOT/.github/workflows/test.yml" \
        "$PROJECT_ROOT/tests/pi_integration.bats" \
        "$PROJECT_ROOT/tests/pi_install.bats" \
        "$PROJECT_ROOT/tests/pi_project_awm.bats" \
        "$PROJECT_ROOT/tests/pi_compatibility_manifest.bats" <<'PY'
import json
import pathlib
import re
import sys

compatibility = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
workflow = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

start = workflow.index("  pi-compatibility:\n")
end = workflow.index("\n  archive-cross-platform:\n", start)
lane = workflow[start:end]

for expected in (
    "timeout-minutes: 40",
    "id: Linux-x86_64-glibc",
    "runner: ubuntu-24.04",
    "id: Darwin-arm64-none",
    "runner: macos-15",
    "id: Darwin-x86_64-none",
    "runner: macos-15-intel",
    "sudo apt-get install -y jq ripgrep zsh",
    "brew install bash jq ripgrep",
    "scripts/dev/native-host/assert-runner-platform.sh",
    "scripts/build-release-archive.sh --verify",
    "id: pi_runtime_snapshot",
    '$RUNNER_TEMP/pi-prefix/node_modules',
    "snapshot-runtime",
    'snapshot_sha256=%s',
    "tests/pi_workflow_contract.bats",
    "tests/pi_evidence_receipt.bats",
    "tests/pi_cell_evidence.bats",
    "tests/pi_integration.bats",
    "tests/pi_install.bats",
    "tests/pi_project_awm.bats",
    "tests/pi_compatibility_manifest.bats",
    "Upload exact-candidate Pi evidence",
    'pi-candidate-${{ matrix.pi.id }}-${{ matrix.target.id }}.tap',
    'pi-candidate-${{ matrix.pi.id }}-${{ matrix.target.id }}.sha256',
    'pi-tests-${{ matrix.pi.id }}-${{ matrix.target.id }}.sha256',
    'pi-cell-${{ matrix.pi.id }}-${{ matrix.target.id }}.json',
    'pi-runtime-pre-${{ matrix.pi.id }}-${{ matrix.target.id }}.json',
    "Bind observed Pi cell identity to exact candidate evidence",
    ".github/scripts/build-pi-cell-evidence.py create",
    ".github/scripts/build-pi-cell-evidence.py verify",
    ".github/schemas/pi-cell-evidence.schema.json",
    '--pi-runtime-root "$runtime_root"',
    '--pi-install-prefix "$RUNNER_TEMP/pi-prefix"',
    '--pre-test-runtime-snapshot "$pre_test_snapshot"',
    '--pre-test-runtime-snapshot-sha256 "$pre_test_snapshot_sha"',
    'test "$(jq -er \'.host.observation_mode\' "$cell")" = native',
):
    assert expected in lane, expected

for forbidden in (
    'printf \'MAINFRAME_PI_PACKAGE_ROOT=%s\\n\'',
    'printf \'MAINFRAME_PI_RUNTIME_ROOT=%s\\n\'',
    '"$MAINFRAME_PI_PACKAGE_ROOT"',
    '"$MAINFRAME_PI_RUNTIME_ROOT"',
):
    assert forbidden not in lane, forbidden

for record in compatibility["certifications"]:
    assert re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", record["npm_integrity"])
    assert f"package: '{record['package']}'" in lane
    assert f"version: '{record['version']}'" in lane
    assert f"integrity: '{record['npm_integrity']}'" in lane

release_start = workflow.index("  release-build:\n")
release_steps = workflow.index("\n    steps:\n", release_start)
release_header = workflow[release_start:release_steps]
assert "pi-compatibility" in release_header
assert "pi-cell-attestation" in release_header
release_end = workflow.index("\n  release-publish:\n", release_start)
release_lane = workflow[release_start:release_end]
candidate_test_count = sum(
    len(re.findall(r"(?m)^\s*@test\s", pathlib.Path(path).read_text(encoding="utf-8")))
    for path in sys.argv[3:]
)
for expected in (
    "pattern: pi-candidate-*",
    'test "${#pi_candidate_digests[@]}" -eq 6',
    'test "${#pi_candidate_tap[@]}" -eq 6',
    'test "${#pi_test_digests[@]}" -eq 6',
    'test "${#pi_cell_receipts[@]}" -eq 6',
    'test "${#pi_runtime_snapshots[@]}" -eq 6',
    'test "${#pi_node_bindings[@]}" -eq 6',
    'test "${#pi_evidence_entries[@]}" -eq 36',
    'test ! -L "$evidence_file"',
    'for pi_id in upstream-0.73.1 fork-0.84.1; do',
    'Darwin-arm64-none Darwin-x86_64-none Linux-x86_64-glibc; do',
    'pi-candidate-${pi_id}-${target_id}.sha256',
    'pi-candidate-${pi_id}-${target_id}.tap',
    'pi-tests-${pi_id}-${target_id}.sha256',
    'pi-cell-${pi_id}-${target_id}.json',
    'pi-node-pre-${pi_id}-${target_id}.json',
    'pi-runtime-pre-${pi_id}-${target_id}.json',
    'pi_evidence="dist/mainframe-${RELEASE_VERSION}.pi-evidence.json"',
    '.github/scripts/build-pi-release-evidence.py create',
    '.github/scripts/build-pi-release-evidence.py verify',
    '--contract .github/pi-evidence-contract.json',
    '--schema .github/schemas/pi-release-evidence.schema.json',
    '--cell-schema .github/schemas/pi-cell-evidence.schema.json',
    '--artifacts-dir gate-evidence/pi',
    'mapfile -t durable_pi_cell_names',
    'test "${#durable_pi_cell_names[@]}" -eq 6',
    'install -m 0644 "$source_cell" "$durable_cell"',
    '--cell-receipts-dir dist',
    '--output "$pi_evidence"',
    '--evidence "$pi_evidence"',
    '([.matrix[] | select(.compatibility.support == "certified")] | length) == 1',
    '([.matrix[] | select(.compatibility.support == "limited")] | length) == 1',
    '([.matrix[] | select(.compatibility.support == "unverified")] | length) == 4',
    '([.matrix[] | select(.observation.mode == "native")] | length) == 6',
    '.summary.planned_tests == 270',
    '.summary.executed == 267',
    '.summary.skipped == 3',
    'pi_evidence_sha256=%s',
    'expected_pi_test_sha=',
    '"$expected_pi_test_sha"',
    '"$digest_file")" = "$archive_sha"',
    f'test "$(grep -Fxc \'1..{candidate_test_count}\' "$tap_file")" -eq 1',
    f'test "$(grep -Ec \'^ok [0-9]+ \' "$tap_file" || true)" -eq {candidate_test_count}',
):
    assert expected in release_lane, expected
print("Pi exact-candidate workflow contract is release-gated")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi exact-candidate workflow contract is release-gated" ]]
}

@test "Pi evidence digest changes when an exact candidate test changes" {
    local staged_root="$BATS_TEST_TMPDIR/pi-evidence-source"
    mkdir -p "$staged_root/tests"
    cp \
        "$PROJECT_ROOT/tests/pi_integration.bats" \
        "$PROJECT_ROOT/tests/pi_install.bats" \
        "$PROJECT_ROOT/tests/pi_project_awm.bats" \
        "$PROJECT_ROOT/tests/pi_compatibility_manifest.bats" \
        "$staged_root/tests/"

    run python3 \
        "$PROJECT_ROOT/scripts/dev/native-host/hash-package-tree.py" \
        "$staged_root" tests
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    local original_digest="$output"

    printf '\n# evidence-integrity mutation canary\n' >> \
        "$staged_root/tests/pi_integration.bats"
    run python3 \
        "$PROJECT_ROOT/scripts/dev/native-host/hash-package-tree.py" \
        "$staged_root" tests
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    [[ "$output" != "$original_digest" ]]
}

@test "Pi workflow binds the same native Node runtime before and after Pi execution" {
    run ruby - "$PROJECT_ROOT/.github/workflows/test.yml" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
steps = workflow.fetch("jobs").fetch("pi-compatibility").fetch("steps")
native_index = steps.index do |step|
  step["name"] == "Assert native candidate platform"
end
node_index = steps.index do |step|
  step["name"] == "Bind native Node.js executable before Pi tests"
end
install_index = steps.index do |step|
  step["name"] == "Install pinned Pi package with lifecycle scripts disabled"
end
execute_index = steps.index do |step|
  step["name"] == "Verify first-party Pi package, hooks, tools, and migration from exact candidate"
end
bind_index = steps.index do |step|
  step["name"] == "Bind observed Pi cell identity to exact candidate evidence"
end
raise "Pi Node binding step inventory drift" unless
  native_index && node_index && install_index && execute_index && bind_index &&
    native_index < node_index && node_index < install_index &&
    install_index < execute_index && execute_index < bind_index

node_step = steps.fetch(node_index)
raise "Pi Node binding step id drift" unless node_step["id"] == "node_runtime_binding"
pre = node_step.fetch("run")
post = steps.fetch(bind_index).fetch("run")

[
  "command -v node",
  "os.path.realpath",
  "snapshot-node",
  '--node-executable "$node_bin"',
  "--expected-os '${{ matrix.target.os }}'",
  "--expected-arch '${{ matrix.target.arch }}'",
  "process.arch",
  'pi-node-pre-${suffix}.json',
  'node_bin=%s',
  'node_binding_sha256=%s'
].each do |fragment|
  raise "pre-test Pi Node binding is missing: #{fragment}" unless pre.include?(fragment)
end

snapshot_index = pre.index("snapshot-node")
process_arch_index = pre.index("process.arch")
output_index = pre.index('node_bin=%s')
raise "Node binding must precede the explicit architecture recheck and output" unless
  snapshot_index && process_arch_index && output_index &&
    snapshot_index < process_arch_index && process_arch_index < output_index

[
  "node_bin='${{ steps.node_runtime_binding.outputs.node_bin }}'",
  'pi-node-pre-${{ matrix.pi.id }}-${{ matrix.target.id }}.json',
  "pre_test_node_binding_sha='${{ steps.node_runtime_binding.outputs.node_binding_sha256 }}'",
  '--node-executable "$node_bin"',
  "--expected-node-arch '${{ matrix.target.arch }}'",
  '--pre-test-node-binding "$pre_test_node_binding"',
  '--pre-test-node-binding-sha256 "$pre_test_node_binding_sha"'
].each do |fragment|
  raise "post-test Pi Node binding is missing: #{fragment}" unless post.include?(fragment)
end

create_index = post.index("build-pi-cell-evidence.py create")
verify_index = post.index("build-pi-cell-evidence.py verify")
raise "receipt creation and verification must both perform the post-test Node recheck" unless
  create_index && verify_index && create_index < verify_index

raise "Pi tests must use the exact pre-admitted Node executable" unless
  steps.fetch(execute_index).fetch("run").include?(
    "export MAINFRAME_PI_NODE_BIN='${{ steps.node_runtime_binding.outputs.node_bin }}'"
  )
RUBY

    [[ "$status" -eq 0 ]]
}

@test "Pi execution is unprivileged and clean downstream validation precedes attestation" {
    run ruby - "$PROJECT_ROOT/.github/workflows/test.yml" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
pi_job = jobs.fetch("pi-compatibility")
raise "Pi execution job must have contents:read only" unless
  pi_job.fetch("permissions") == {"contents" => "read"}
%w[actions artifact-metadata attestations id-token].each do |permission|
  raise "Pi execution regained #{permission} privilege" if
    pi_job.fetch("permissions").key?(permission)
end

pi_steps = pi_job.fetch("steps")
checkout = pi_steps.find { |step| step["name"] == "Checkout" }
raise "Pi checkout must not persist credentials" unless
  checkout && checkout.fetch("with").fetch("persist-credentials") == false
raise "Pi execution job must not invoke an attestation action" if
  pi_steps.any? { |step| step.fetch("uses", "").start_with?("actions/attest@") }

pi_execution_jobs = jobs.select do |_name, job|
  scripts = job.fetch("steps", []).map { |step| step.fetch("run", "") }.join("\n")
  scripts.include?("node_modules/.bin/pi") || scripts.include?("MAINFRAME_PI_BIN")
end
raise "unexpected Pi execution job inventory" unless
  pi_execution_jobs.keys.sort == %w[pi-compatibility stable-core-conformance-linux]
pi_execution_jobs.each do |name, job|
  raise "#{name} must have contents:read only" unless
    job.fetch("permissions") == {"contents" => "read"}
  job_checkout = job.fetch("steps").find do |step|
    step.fetch("uses", "").start_with?("actions/checkout@")
  end
  raise "#{name} checkout must not persist credentials" unless
    job_checkout &&
      job_checkout.fetch("with", {}).fetch("persist-credentials", nil) == false
  raise "#{name} must not invoke attestation" if
    job.fetch("steps").any? do |step|
      step.fetch("uses", "").start_with?("actions/attest@")
    end
end
install = pi_steps.find { |step| step["name"] ==
  "Install pinned Pi package with lifecycle scripts disabled" }
raise "Pi runtime snapshot step id drift" unless
  install && install["id"] == "pi_runtime_snapshot"
install_script = install.fetch("run")
[
  'pi_prefix="$RUNNER_TEMP/pi-prefix"',
  'runtime_root="$RUNNER_TEMP/pi-prefix/node_modules"',
  'package_root="$runtime_root/$PI_PACKAGE"',
  "snapshot-runtime",
  '--pi-install-prefix "$pi_prefix"',
  "/usr/bin/env -i",
  "/usr/bin/python3",
  'printf \'snapshot_sha256=%s\\n\''
].each do |fragment|
  raise "Pi fixed runtime snapshot is missing: #{fragment}" unless
    install_script.include?(fragment)
end
raise "Pi runtime path leaked through GITHUB_ENV" if
  install_script.include?("GITHUB_ENV")
raise "Pi runtime snapshot must precede Pi execution" unless
  install_script.index("snapshot-runtime") <
    install_script.index('test "$("$pi_bin" --version 2>&1)"')

bind_index = pi_steps.index { |step| step["name"] ==
  "Bind observed Pi cell identity to exact candidate evidence" }
upload_index = pi_steps.index { |step| step["name"] ==
  "Upload exact-candidate Pi evidence" }
raise "Pi evidence binding/upload order drift" unless
  bind_index && upload_index && bind_index < upload_index

bind = pi_steps.fetch(bind_index)
raise "production Pi cell binding enables test override" if
  bind.fetch("env", {}).key?("MAINFRAME_PI_CELL_TEST_MODE") ||
    bind.fetch("run").include?("MAINFRAME_PI_CELL_TEST_MODE")
[
  'runtime_root="$RUNNER_TEMP/pi-prefix/node_modules"',
  'package_root="$runtime_root/${{ matrix.pi.package }}"',
  '--pi-package-root "$package_root"',
  '--pi-runtime-root "$runtime_root"',
  '--pi-install-prefix "$RUNNER_TEMP/pi-prefix"',
  '--pre-test-runtime-snapshot "$pre_test_snapshot"',
  '--pre-test-runtime-snapshot-sha256 "$pre_test_snapshot_sha"',
  "/usr/bin/env -i",
  "/usr/bin/python3",
  '"${clean_python[@]}" .github/scripts/build-pi-cell-evidence.py create',
  '"${clean_python[@]}" .github/scripts/build-pi-cell-evidence.py verify'
].each do |fragment|
  raise "Pi evidence binding does not derive fixed runtime: #{fragment}" unless
    bind.fetch("run").include?(fragment)
end
raise "Pi evidence binding trusts exported package/runtime roots" if
  bind.fetch("run").include?("MAINFRAME_PI_PACKAGE_ROOT") ||
    bind.fetch("run").include?("MAINFRAME_PI_RUNTIME_ROOT")

signing_job = jobs.fetch("pi-cell-attestation")
raise "Pi signer must wait for every Pi matrix cell" unless
  signing_job.fetch("needs") == ["pi-compatibility", "release-tag-identity"]
raise "Pi signer condition drift" unless signing_job.fetch("if") ==
  "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')"
expected_signing_permissions = {
  "actions" => "read",
  "artifact-metadata" => "write",
  "attestations" => "write",
  "contents" => "read",
  "id-token" => "write"
}
raise "Pi signer permissions drift" unless
  signing_job.fetch("permissions") == expected_signing_permissions

signing_steps = signing_job.fetch("steps")
signing_checkout = signing_steps.find { |step| step["name"] ==
  "Checkout trusted evidence validators" }
raise "Pi signer checkout must not persist credentials" unless
  signing_checkout &&
    signing_checkout.fetch("with").fetch("persist-credentials") == false &&
    signing_checkout.fetch("with").fetch("fetch-depth") == 0
download_index = signing_steps.index { |step| step["name"] ==
  "Download all exact-candidate Pi evidence" }
validation_index = signing_steps.index { |step| step["name"] ==
  "Strictly validate all Pi cell evidence before signing" }
raise "Pi signer download/validation order drift" unless
  download_index && validation_index && download_index < validation_index
download = signing_steps.fetch(download_index)
raise "Pi signer must download all six named matrix artifacts" unless
  download.fetch("with") == {
    "pattern" => "pi-candidate-*",
    "path" => "gate-evidence/pi",
    "merge-multiple" => true
  }

signing_script = signing_steps.fetch(validation_index).fetch("run")
[
  'test "$GITHUB_REF" = "$tag_ref"',
  'test "$(git rev-parse HEAD)" = "$(git rev-parse "$tag_ref^{commit}")"',
  'test "$GITHUB_REF_NAME" = "v$version"',
  "mapfile -t evidence_files",
  'test "${#evidence_files[@]}" -eq 36',
  'test ! -L "$evidence_file"',
  'test "$(stat -c \'%h\' "$evidence_file")" -eq 1',
  'for pi_id in fork-0.84.1 upstream-0.73.1; do',
  'Darwin-arm64-none Darwin-x86_64-none Linux-x86_64-glibc; do',
  'pi-candidate-${suffix}.sha256',
  'pi-candidate-${suffix}.tap',
  'pi-tests-${suffix}.sha256',
  'pi-cell-${suffix}.json',
  'pi-node-pre-${suffix}.json',
  'pi-runtime-pre-${suffix}.json',
  ".node_runtime.pre_test == .node_runtime.post_test",
  'has("path") | not',
  '"${pi_id}@${target_id}"',
  "scripts/build-release-archive.sh --verify",
  ".github/scripts/build-pi-release-evidence.py create",
  ".github/scripts/build-pi-release-evidence.py verify",
  "--artifacts-dir gate-evidence/pi",
  '--workflow-run-id "$GITHUB_RUN_ID"',
  '--workflow-run-attempt "$GITHUB_RUN_ATTEMPT"',
  '([.matrix[].observation.mode] | all(. == "native"))',
  '([.matrix[].result.status] | all(. == "pass"))',
  'for cell_receipt in gate-evidence/pi/pi-cell-*.json; do',
  'signing_subject="$RUNNER_TEMP/$cell_name"',
  'test ! -e "$signing_subject"',
  'install -m 0644 "$cell_receipt" "$signing_subject"',
  'sha256sum "$signing_subject"'
].each do |fragment|
  raise "Pi signer validation is missing: #{fragment}" unless
    signing_script.include?(fragment)
end
raise "Pi signer enables a test-only observation override" if
  signing_script.include?("MAINFRAME_PI_CELL_TEST_MODE")

signing_steps.each do |step|
  script = step.fetch("run", "")
  uses = step.fetch("uses", "")
  raise "credentialed Pi signer installs or executes Pi/package code" if
    uses.start_with?("actions/setup-node@") ||
      script.match?(/(^|\s)npm(?:\s|$)/) ||
      script.include?("pi-coding-agent") ||
      script.include?("node_modules/.bin/pi") ||
      script.include?("MAINFRAME_PI_BIN") ||
      script.include?("tests/bats/bin/bats")
end

attest_steps = signing_steps.select do |step|
  step.fetch("uses", "").start_with?("actions/attest@")
end
expected_subjects = [
  "${{ runner.temp }}/pi-cell-fork-0.84.1-Darwin-arm64-none.json",
  "${{ runner.temp }}/pi-cell-fork-0.84.1-Darwin-x86_64-none.json",
  "${{ runner.temp }}/pi-cell-fork-0.84.1-Linux-x86_64-glibc.json",
  "${{ runner.temp }}/pi-cell-upstream-0.73.1-Darwin-arm64-none.json",
  "${{ runner.temp }}/pi-cell-upstream-0.73.1-Darwin-x86_64-none.json",
  "${{ runner.temp }}/pi-cell-upstream-0.73.1-Linux-x86_64-glibc.json",
]
raise "Pi signer must emit six one-subject attestations" unless
  attest_steps.length == 6 &&
    attest_steps.map { |step| step.fetch("with").keys } ==
      Array.new(6, ["subject-path"]) &&
    attest_steps.map { |step| step.fetch("with").fetch("subject-path") } ==
      expected_subjects
attest_steps.each do |step|
  raise "Pi cell attestation action pin drift" unless step.fetch("uses") ==
    "actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d"
  raise "Pi cell attestation must follow strict validation" unless
    signing_steps.index(step) > validation_index
end

release_job = jobs.fetch("release-build")
raise "release build can bypass Pi signer" unless
  release_job.fetch("needs").include?("pi-cell-attestation")
release_steps = release_job.fetch("steps")
release_download_index = release_steps.index { |step| step["name"] ==
  "Download exact-candidate Pi evidence" }
verify_index = release_steps.index { |step| step["name"] ==
  "Verify exact Pi cell attestations" }
aggregate_index = release_steps.index { |step| step["name"] ==
  "Bind gate evidence to final release bytes" }
raise "Pi cell verification order drift" unless
  release_download_index && verify_index && aggregate_index &&
    release_download_index < verify_index && verify_index < aggregate_index

verify = release_steps.fetch(verify_index)
raise "Pi cell attestation token missing" unless
  verify.fetch("env").fetch("GH_TOKEN") == "${{ github.token }}"
script = verify.fetch("run")
[
  "mapfile -t pi_cell_receipts",
  'test "${#pi_cell_receipts[@]}" -eq 6',
  'expected_invocation="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}"',
  'for pi_id in fork-0.84.1 upstream-0.73.1; do',
  'Darwin-arm64-none Darwin-x86_64-none Linux-x86_64-glibc; do',
  'test "${pi_cell_receipts[$expected_index]}" = "$cell_receipt"',
  'test "$(jq -er \'.cell_id\' "$cell_receipt")" = "${pi_id}@${target_id}"',
  'test "$(jq -er \'.source.workflow_run_id\' "$cell_receipt")" =',
  'test "$(jq -er \'.source.workflow_run_attempt\' "$cell_receipt")" =',
  'test "$(jq -er \'.source.commit_sha\' "$cell_receipt")" =',
  'test "$(jq -er \'.source.ref\' "$cell_receipt")" = "$GITHUB_REF"',
  'gh attestation verify "$cell_receipt"',
  '--repo "$GITHUB_REPOSITORY"',
  "--predicate-type https://slsa.dev/provenance/v1",
  '--signer-workflow "$GITHUB_REPOSITORY/.github/workflows/test.yml"',
  '--signer-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-ref "$GITHUB_REF"',
  "--deny-self-hosted-runners",
  "--limit 100",
  "--format json",
  '.verificationResult.statement.subject == [',
  '.verificationResult.statement.predicate.runDetails.metadata.invocationId ==',
  '.verificationResult.signature.certificate.runInvocationURI ==',
  '.verificationResult.signature.certificate.runnerEnvironment =='
].each do |fragment|
  raise "Pi cell verification is missing: #{fragment}" unless script.include?(fragment)
end
raise "release aggregation enables Pi test override" if
  release_steps.fetch(aggregate_index).fetch("run").include?("MAINFRAME_PI_CELL_TEST_MODE")
aggregate_script = release_steps.fetch(aggregate_index).fetch("run")
[
  'mapfile -t durable_pi_cell_names',
  'test "${#durable_pi_cell_names[@]}" -eq 6',
  'install -m 0644 "$source_cell" "$durable_cell"',
  'expected_cell_sha="$(jq -er --arg name "$cell_name"',
  '--cell-receipts-dir dist'
].each do |fragment|
  raise "durable Pi cell staging is missing: #{fragment}" unless
    aggregate_script.include?(fragment)
end
puts "Pi split-trust attestation contract valid"
RUBY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi split-trust attestation contract valid" ]]
}

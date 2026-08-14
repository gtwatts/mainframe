#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    WORKFLOW="$PROJECT_ROOT/.github/workflows/test.yml"
    MAKEFILE="$PROJECT_ROOT/Makefile"
}

@test "release workflow YAML and release-job shell blocks parse" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "open3"
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
%w[release-tag-identity pi-cell-attestation mcp-package-test
   mcp-package-attestation release-build release-publish].each do |job_name|
  job = jobs.fetch(job_name)
  job.fetch("steps").each do |step|
    next unless step.key?("run")

    script = step.fetch("run").gsub(/\$\{\{[^}]+\}\}/, "GITHUB_EXPRESSION")
    _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: script)
    raise "#{job_name}/#{step.fetch("name")}: #{stderr}" unless status.success?
  end
end
puts "release YAML and shell syntax valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "release YAML and shell syntax valid" ]]
}

@test "full Bats jobs retain bounded timeouts for the complete serial suite" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
expected_steps = {
  "test-linux" => "Run full Bats matrix",
  "test-macos" => "Run full Bats matrix",
  "bash-44-compat" => "Run full Bats matrix under Bash 4.4"
}

expected_steps.each do |job_name, step_name|
  step = jobs.fetch(job_name).fetch("steps").find do |candidate|
    candidate["name"] == step_name
  end
  raise "#{job_name} full Bats step missing" unless step
  raise "#{job_name} full Bats timeout drift" unless
    step.fetch("timeout-minutes") == 180
end

raise "Bash 4.4 job timeout drift" unless
  jobs.fetch("bash-44-compat").fetch("timeout-minutes") == 210

bash44_dependencies = jobs.fetch("bash-44-compat").fetch("steps").find do |candidate|
  candidate["name"] == "Install test and build dependencies"
end
raise "Bash 4.4 dependency step missing" unless bash44_dependencies
raise "Bash 4.4 zsh dependency missing" unless
  bash44_dependencies.fetch("run").match?(/sudo apt-get install -y[^\n]*\bzsh\b/)

bash44_build = jobs.fetch("bash-44-compat").fetch("steps").find do |candidate|
  candidate["name"] == "Build integrity-pinned Bash 4.4.0"
end
raise "Bash 4.4 build step missing" unless bash44_build
bash44_script = bash44_build.fetch("run")
[
  "reviewed_bash=/usr/local/bin/bash",
  'test ! -e "$reviewed_bash" && test ! -L "$reviewed_bash"',
  'sudo /usr/bin/install -o root -g root -m 0755',
  'cmp -s "$prefix/bin/bash" "$reviewed_bash"',
  %(test "$(stat -c '%a' "$reviewed_bash")" = 755),
  'bash44="$reviewed_bash"',
  %(printf '%s\\n' "$(dirname "$reviewed_bash")" >> "$GITHUB_PATH")
].each do |fragment|
  raise "Bash 4.4 reviewed path binding missing: #{fragment}" unless
    bash44_script.include?(fragment)
end
raise "Bash 4.4 scratch prefix must not enter later test PATH" if
  bash44_script.include?(%(printf '%s/bin\\n' "$prefix" >> "$GITHUB_PATH"))

uv_jobs = {
  "test-linux" => "aab924fd522efd06f1c5f3b93a243864fc453132c94b2dc49f1371b528a4b967",
  "bash-44-compat" => "aab924fd522efd06f1c5f3b93a243864fc453132c94b2dc49f1371b528a4b967",
  "test-macos" => "ed336d0ba49db8ef89b2b41fffa372ce63bd032f22a56f001c265891aec32829"
}
uv_jobs.each do |job_name, checksum|
  step = jobs.fetch(job_name).fetch("steps").find do |candidate|
    candidate["name"] == "Set up pinned uv"
  end
  raise "#{job_name} pinned uv setup missing" unless step
  raise "#{job_name} setup-uv action pin drift" unless step.fetch("uses") ==
    "astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b"
  settings = step.fetch("with")
  raise "#{job_name} uv version drift" unless settings.fetch("version") == "0.11.32"
  raise "#{job_name} uv cache must stay disabled" unless settings["enable-cache"] == false
  raise "#{job_name} uv checksum drift" unless settings.fetch("checksum") == checksum
end

mac_dependencies = jobs.fetch("test-macos").fetch("steps").find do |candidate|
  candidate["name"] == "Install dependencies"
end
raise "macOS full Bats dependency step missing" unless mac_dependencies
raise "macOS full Bats ripgrep dependency missing" unless
  mac_dependencies.fetch("run").include?("brew install jq bash coreutils parallel csvkit xmlstarlet ripgrep")

puts "full Bats timeout and dependency contract valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "full Bats timeout and dependency contract valid" ]]
}

@test "Homebrew tap creation uses Homebrew-scoped CI Git identity" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
steps = workflow.fetch("jobs").fetch("homebrew-package").fetch("steps")
step = steps.find { |item| item["name"] == "Install and test from an ephemeral tap" }
raise "ephemeral Homebrew tap step missing" unless step
environment = step.fetch("env")
raise "Homebrew Git name drift" unless environment["HOMEBREW_GIT_NAME"] == "MAINFRAME CI"
raise "Homebrew Git email drift" unless
  environment["HOMEBREW_GIT_EMAIL"] == "mainframe-ci@example.invalid"
raise "raw Git identity must not replace Homebrew's scoped identity" unless
  environment.keys.grep(/\AGIT_(?:AUTHOR|COMMITTER)_/).empty?
raise "ephemeral tap creation missing" unless step.fetch("run").include?('brew tap-new "$tap"')
puts "Homebrew tap CI identity contract valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Homebrew tap CI identity contract valid" ]]
}

@test "release tuple aggregation jq programs compile and execute" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "json"
require "open3"
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
steps = workflow.fetch("jobs").fetch("release-build").fetch("steps")
script = steps.find { |step| step["name"] == "Bind gate evidence to final release bytes" }
  .fetch("run")
quoted_programs = script.scan(/'([^']*)'/m).flatten
bad_continuations = quoted_programs.select { |program| program.include?("\\\n") }
raise "shell continuation leaked into a single-quoted jq program" unless bad_continuations.empty?

platform_filter = quoted_programs.find { |program| program.include?("map(.platform.os") }
unique_filter = quoted_programs.find do |program|
  program.include?('.host + ":" + .os') && program.include?("unique | length")
end
raise "release tuple jq filters missing" unless platform_filter && unique_filter

awm = [
  {"platform" => {"os" => "Darwin", "arch" => "arm64", "system_libc" => "none"}},
  {"platform" => {"os" => "Darwin", "arch" => "x86_64", "system_libc" => "none"}},
  {"platform" => {"os" => "Linux", "arch" => "x86_64", "system_libc" => "glibc"}}
]
stdout, stderr, status = Open3.capture3("jq", "-s", "-r", platform_filter,
  stdin_data: awm.map { |item| JSON.generate(item) }.join("\n"))
raise "AWM tuple filter failed: #{stderr}" unless status.success?
raise "AWM tuple filter result drift" unless stdout.strip ==
  "Darwin-arm64-none,Darwin-x86_64-none,Linux-x86_64-glibc"

safety = %w[gemini codex copilot claude].flat_map do |host|
  [
    {"host" => host, "os" => "Darwin", "arch" => "arm64", "system_libc" => "none"},
    {"host" => host, "os" => "Darwin", "arch" => "x86_64", "system_libc" => "none"},
    {"host" => host, "os" => "Linux", "arch" => "x86_64", "system_libc" => "glibc"}
  ]
end
stdout, stderr, status = Open3.capture3("jq", "-s", unique_filter,
  stdin_data: safety.map { |item| JSON.generate(item) }.join("\n"))
raise "safety uniqueness filter failed: #{stderr}" unless status.success?
raise "safety uniqueness count drift" unless stdout.strip == "12"

puts "release tuple jq programs valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "release tuple jq programs valid" ]]
}

@test "CI and local Bats plus uv dependencies are integrity pinned" {
    run ruby - "$WORKFLOW" "$MAKEFILE" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
makefile = File.read(ARGV.fetch(1))
expected = {
  "BATS_CORE_COMMIT" => ["eb7f42f8d608ac693d7a4b67474f6714ea68cfc5", "bats", "bats-core", "v1.14.0", 8],
  "BATS_SUPPORT_COMMIT" => ["24a72e14349690bcbf7c151b9d2d1cdd32d36eb1", "bats-support", "bats-support", "v0.3.0", 5],
  "BATS_ASSERT_COMMIT" => ["f1e9280eaae8f86cbe278a687e6ba755bc802c1a", "bats-assert", "bats-assert", "v2.2.4", 5],
  "BATS_FILE_COMMIT" => ["13ad5e2ffcc360281432db3d43a306f7b3667d60", "bats-file", "bats-file", "v0.4.0", 4]
}
runs = workflow.fetch("jobs").values.flat_map do |job|
  job.fetch("steps", []).map { |step| step["run"] }.compact
end
all_runs = runs.join("\n")
expected.each do |variable, (commit, directory, repository, tag, count)|
  raise "workflow #{variable} pin drift" unless workflow.fetch("env")[variable] == commit
  clone = "git clone --no-checkout --depth 1 --branch #{tag} " \
    "https://github.com/bats-core/#{repository}.git tests/#{directory}"
  checkout = %(git -C tests/#{directory} checkout --detach "$#{variable}")
  verify = %(test "$(git -C tests/#{directory} rev-parse HEAD)" = "$#{variable}")
  raise "#{directory} source tag count drift" unless all_runs.scan(clone).length == count
  raise "#{directory} checkout count drift" unless all_runs.scan(checkout).length == count
  raise "#{directory} verification count drift" unless all_runs.scan(verify).length == count
  raise "Makefile #{variable} pin missing" unless makefile.include?("#{variable} := #{commit}")
  raise "Makefile #{directory} exact dependency missing" unless
    makefile.include?(%q[ensure_dep https://github.com/bats-core/]) &&
    makefile.include?(%Q["$(#{variable})"])
end

raise "moving uv installer remains" if all_runs.include?("astral.sh/uv/install.sh")
trust_steps = workflow.fetch("jobs").fetch("trust-gates").fetch("steps")
uv = trust_steps.find { |step| step["name"] == "Set up integrity-pinned uv" }
raise "pinned uv setup missing" unless uv
raise "setup-uv action pin drift" unless uv.fetch("uses") ==
  "astral-sh/setup-uv@08807647e7069bb48b6ef5acd8ec9567f424441b"
raise "uv version drift" unless uv.fetch("with").fetch("version") == "0.11.32"
raise "uv checksum drift" unless uv.fetch("with").fetch("checksum") ==
  "aab924fd522efd06f1c5f3b93a243864fc453132c94b2dc49f1371b528a4b967"
raise "uv lock enforcement missing" unless all_runs.include?("uv run --locked --group dev")

puts "test dependency pins valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "test dependency pins valid" ]]
}

@test "release tag identity binds the raw pushed ref before any signing authority" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
identity = jobs.fetch("release-tag-identity")
raise "identity gate must remain unprivileged" unless
  identity.fetch("permissions") == {"contents" => "read"}
raise "identity outputs drift" unless identity.fetch("outputs") == {
  "version" => "${{ steps.identity.outputs.version }}",
  "tag_ref_sha" => "${{ steps.identity.outputs.tag_ref_sha }}",
  "tag_commit" => "${{ steps.identity.outputs.tag_commit }}"
}
script = identity.fetch("steps").find do |step|
  step["name"] == "Validate exact new tag on main"
end.fetch("run")
required = [
  'test "${{ github.event.created }}" = true',
  'tag_ref_sha="$(git rev-parse "$GITHUB_REF")"',
  'tag_commit="$(git rev-parse "$GITHUB_REF^{commit}")"',
  'test "$tag_ref_sha" = "${{ github.event.after }}"',
  'test "$(git rev-parse HEAD)" = "$tag_commit"',
  'git merge-base --is-ancestor "$tag_commit" refs/remotes/origin/main'
]
required.each do |fragment|
  raise "identity gate missing: #{fragment}" unless script.include?(fragment)
end

release_script = jobs.fetch("release-build").fetch("steps").find do |step|
  step["name"] == "Validate release tag"
end.fetch("run")
[
  '"${{ needs.release-tag-identity.outputs.version }}"',
  '"${{ needs.release-tag-identity.outputs.tag_ref_sha }}"',
  '"${{ needs.release-tag-identity.outputs.tag_commit }}"',
  "release tag identity changed after the unprivileged identity gate"
].each do |fragment|
  raise "release identity handoff missing: #{fragment}" unless
    release_script.include?(fragment)
end
handoff_index = release_script.index("release tag identity changed")
checkout_index = release_script.index('git rev-parse HEAD')
raise "release identity must be checked before later signing inputs" unless
  handoff_index && checkout_index && handoff_index < checkout_index
puts "release tag identity handoff valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "release tag identity handoff valid" ]]
}

@test "MCP release consumes one tested artifact ID and preserves separate SLSA provenance" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
build = jobs.fetch("mcp-package-build")
test_job = jobs.fetch("mcp-package-test")
signer = jobs.fetch("mcp-package-attestation")
release = jobs.fetch("release-build")

raise "MCP build must remain unprivileged" unless
  build.fetch("permissions") == {"contents" => "read"}
raise "MCP artifact ID output drift" unless build.fetch("outputs") == {
  "candidate_artifact_id" => "${{ steps.upload_candidate.outputs.artifact-id }}"
}
upload = build.fetch("steps").find do |step|
  step["name"] == "Upload unexecuted package candidate"
end
raise "MCP upload step id drift" unless upload.fetch("id") == "upload_candidate"
expected_candidate_paths = [
  "${{ runner.temp }}/mainframe-mcp-candidate/mainframe_mcp-10.2.0-py3-none-any.whl",
  "${{ runner.temp }}/mainframe-mcp-candidate/mainframe_mcp-10.2.0.tar.gz",
  "${{ runner.temp }}/mainframe-mcp-candidate/mainframe-10.2.0.tar.gz",
  "${{ runner.temp }}/mainframe-mcp-candidate/mainframe-mcp-candidate.sha256"
]
actual_candidate_paths = upload.fetch("with").fetch("path").lines.map(&:strip).reject(&:empty?)
raise "MCP build artifact inventory drift" unless
  actual_candidate_paths == expected_candidate_paths

expected_build_id = "${{ needs.mcp-package-build.outputs.candidate_artifact_id }}"
[test_job, signer].each do |job|
  download = job.fetch("steps").find do |step|
    step["name"].start_with?("Download exact")
  end
  inputs = download.fetch("with")
  raise "MCP consumer must use the exact artifact ID" unless
    inputs["artifact-ids"] == expected_build_id &&
      inputs["merge-multiple"] == true &&
      !inputs.key?("name")
end
raise "MCP signer trust order drift" unless signer.fetch("needs") ==
  ["mcp-package-build", "mcp-package-test", "release-tag-identity"]
raise "MCP signer artifact output drift" unless signer.fetch("outputs") == {
  "candidate_artifact_id" => expected_build_id
}
expected_subjects = [
  ["Attest tested MAINFRAME MCP wheel",
   "${{ runner.temp }}/mainframe-mcp-candidate/mainframe_mcp-10.2.0-py3-none-any.whl"],
  ["Attest tested MAINFRAME MCP source distribution",
   "${{ runner.temp }}/mainframe-mcp-candidate/mainframe_mcp-10.2.0.tar.gz"],
  ["Attest deterministic MAINFRAME MCP runtime-pair manifest",
   "${{ runner.temp }}/mainframe-mcp-candidate/mainframe-mcp-candidate.sha256"]
]
expected_subjects.each do |name, subject|
  step = signer.fetch("steps").find { |candidate| candidate["name"] == name }
  raise "MCP attestation missing: #{name}" unless step
  raise "MCP attestation action pin drift" unless step.fetch("uses") ==
    "actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d"
  raise "MCP SLSA subject drift: #{name}" unless
    step.fetch("with") == {"subject-path" => subject}
end

release_download = release.fetch("steps").find do |step|
  step["name"] == "Download the tested MCP-bound runtime and packages"
end
release_inputs = release_download.fetch("with")
raise "release must consume the signer-propagated artifact ID" unless
  release_inputs["artifact-ids"] ==
    "${{ needs.mcp-package-attestation.outputs.candidate_artifact_id }}" &&
  release_inputs["merge-multiple"] == true &&
  !release_inputs.key?("name")
stage = release.fetch("steps").find do |step|
  step["name"] == "Verify exact MCP release candidate"
end
raise "MCP staging output id drift" unless stage.fetch("id") == "mcp_release_assets"
stage_script = stage.fetch("run")
[
  "MCP candidate artifact inventory is not exact",
  "MCP runtime-pair manifest record count is not exact",
  "MCP runtime-pair manifest order or syntax is invalid",
  "MCP candidate digest mismatch",
  "MCP-tested runtime differs from release runtime",
  'f"{label} runtime binding does not match the release inventory"',
  "wheel_sha256=%s",
  "sdist_sha256=%s",
  "manifest_sha256=%s"
].each do |fragment|
  raise "MCP staging contract missing: #{fragment}" unless
    stage_script.include?(fragment)
end
provenance_step = release.fetch("steps").find do |step|
  step["name"] == "Verify exact MCP package provenance"
end
publish_stage = release.fetch("steps").find do |step|
  step["name"] == "Stage provenance-verified MCP release assets"
end
stage_env = publish_stage.fetch("env")
{
  "EXPECTED_MCP_WHEEL_SHA" => "${{ steps.mcp_release_assets.outputs.wheel_sha256 }}",
  "EXPECTED_MCP_SDIST_SHA" => "${{ steps.mcp_release_assets.outputs.sdist_sha256 }}",
  "EXPECTED_MCP_MANIFEST_SHA" => "${{ steps.mcp_release_assets.outputs.manifest_sha256 }}"
}.each do |key, value|
  raise "MCP staging env #{key} drift" unless stage_env[key] == value
end
publish_stage_script = publish_stage.fetch("run")
[
  'install -m 0644 -- "$wheel"',
  'install -m 0644 -- "$sdist"',
  'install -m 0644 -- "$pair_manifest"',
  '"$EXPECTED_MCP_WHEEL_SHA"',
  '"$EXPECTED_MCP_SDIST_SHA"',
  '"$EXPECTED_MCP_MANIFEST_SHA"'
].each do |fragment|
  raise "MCP verified staging missing: #{fragment}" unless
    publish_stage_script.include?(fragment)
end
release_steps = release.fetch("steps")
download_index = release_steps.index(release_download)
candidate_index = release_steps.index(stage)
provenance_index = release_steps.index(provenance_step)
publish_stage_index = release_steps.index(publish_stage)
raise "MCP release ordering is unsafe" unless
  download_index && candidate_index && provenance_index && publish_stage_index &&
    download_index < candidate_index && candidate_index < provenance_index &&
    provenance_index < publish_stage_index
all_release_scripts = [release, jobs.fetch("release-publish")].flat_map do |job|
  job.fetch("steps").map { |step| step["run"] }.compact
end.join("\n")
raise "privileged release path must not rebuild MCP packages" if
  all_release_scripts.include?("build-mcp-package.py") ||
  all_release_scripts.include?("uv build")

verify = provenance_step.fetch("run")
[
  'expected_invocation_prefix="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/"',
  '--predicate-type https://slsa.dev/provenance/v1',
  '--signer-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-ref "$GITHUB_REF"',
  '.verificationResult.statement.subject == [',
  '.verificationResult.statement.predicate.runDetails.metadata.invocationId',
  '.verificationResult.signature.certificate.runInvocationURI',
  '.verificationResult.signature.certificate.runnerEnvironment',
  '--argjson max_attempt "$GITHUB_RUN_ATTEMPT"'
].each do |fragment|
  raise "MCP provenance verification missing: #{fragment}" unless
    verify.include?(fragment)
end

exercise = test_job.fetch("steps").find do |step|
  step["name"] == "Exercise package and exact runtime from outside the checkout"
end
raise "offline pipx acceptance gate missing" unless
  exercise.fetch("env")["MAINFRAME_MCP_REQUIRE_PIPX_OFFLINE"] == "1"
puts "MCP artifact and provenance graph valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "MCP artifact and provenance graph valid" ]]
}

@test "release build orders the final archive before the exact evidence graph" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
jobs = workflow.fetch("jobs")
job = jobs.fetch("release-build")
expected_permissions = {
  "actions" => "read",
  "artifact-metadata" => "write",
  "contents" => "read",
  "attestations" => "write",
  "id-token" => "write"
}
raise "release-build permissions drift" unless job.fetch("permissions") == expected_permissions

pi_execution = jobs.fetch("pi-compatibility")
pi_signer = jobs.fetch("pi-cell-attestation")
raise "Pi execution must not receive release-signing credentials" unless
  pi_execution.fetch("permissions") == {"contents" => "read"}
raise "Pi signer must be downstream of every Pi execution cell" unless
  pi_signer.fetch("needs") == ["pi-compatibility", "release-tag-identity"]
needs = job.fetch("needs")
pi_execution_index = needs.index("pi-compatibility")
pi_signer_index = needs.index("pi-cell-attestation")
raise "release build must require the clean Pi signer" unless
  pi_execution_index && pi_signer_index &&
    pi_signer_index == pi_execution_index + 1

expected_outputs = {
  "version" => "${{ steps.version.outputs.version }}",
  "tag_ref_sha" => "${{ steps.version.outputs.tag_ref_sha }}",
  "tag_commit" => "${{ steps.version.outputs.tag_commit }}",
  "release_archive_sha256" => "${{ steps.release_evidence.outputs.archive_sha256 }}",
  "release_checksum_sha256" => "${{ steps.release_evidence.outputs.checksum_sha256 }}",
  "release_sbom_sha256" => "${{ steps.release_evidence.outputs.sbom_sha256 }}",
  "release_formula_sha256" => "${{ steps.release_evidence.outputs.formula_sha256 }}",
  "release_evidence_manifest_sha256" => "${{ steps.release_evidence.outputs.manifest_sha256 }}",
  "release_evidence_bundle_sha256" => "${{ steps.release_evidence.outputs.bundle_sha256 }}",
  "release_pi_evidence_sha256" => "${{ steps.release_evidence.outputs.pi_evidence_sha256 }}",
  "release_mcp_wheel_sha256" => "${{ steps.mcp_release_assets.outputs.wheel_sha256 }}",
  "release_mcp_sdist_sha256" => "${{ steps.mcp_release_assets.outputs.sdist_sha256 }}",
  "release_mcp_manifest_sha256" => "${{ steps.mcp_release_assets.outputs.manifest_sha256 }}"
}
raise "release-build outputs drift" unless job.fetch("outputs") == expected_outputs

steps = job.fetch("steps")
names = steps.map { |step| step.fetch("name") }
archive_index = names.index("Build and verify runtime archive")
bind_index = names.index("Bind gate evidence to final release bytes")
attest_index = names.index("Attest release evidence predicate")
raise "release step ordering is incomplete" unless archive_index && bind_index && attest_index
raise "archive/evidence ordering is unsafe" unless archive_index < bind_index && bind_index < attest_index

bind = steps.fetch(bind_index)
raise "release evidence step id drift" unless bind.fetch("id") == "release_evidence"
expected_bind_env = {
  "RELEASE_VERSION" => "${{ steps.version.outputs.version }}",
  "TAG_REF_SHA" => "${{ steps.version.outputs.tag_ref_sha }}",
  "TAG_COMMIT" => "${{ steps.version.outputs.tag_commit }}"
}
raise "release evidence environment drift" unless bind.fetch("env") == expected_bind_env
script = bind.fetch("run")
common_flags = %w[
  --repo-root --repository --version --tag --tag-ref --tag-ref-sha
  --tag-commit-sha --workflow-run-id --workflow-run-attempt
  --source-date-epoch --archive --manifest --bundle
]
common_flags.each { |flag| raise "missing #{flag}" unless script.include?(flag) }
required_fragments = [
  "release_evidence_common=(",
  "release_evidence_inputs=()",
  'release_evidence_inputs+=(--safety-evidence "$evidence")',
  'release_evidence_inputs+=(--awm-evidence "$evidence")',
  'create "${release_evidence_common[@]}" "${release_evidence_inputs[@]}"',
  'verify "${release_evidence_common[@]}"',
  'expected_platforms="Darwin-arm64-none,Darwin-x86_64-none,Linux-x86_64-glibc"',
  'test "${#all_native_evidence[@]}" -eq 12',
  'test "${#awm_chain_evidence[@]}" -eq 3',
  'test "${#pi_candidate_digests[@]}" -eq 6',
  'test "${#pi_candidate_tap[@]}" -eq 6',
  'test "${#pi_test_digests[@]}" -eq 6',
  'test "${#pi_cell_receipts[@]}" -eq 6',
  'test "${#pi_runtime_snapshots[@]}" -eq 6',
  'mapfile -t pi_node_bindings',
  'test "${#pi_node_bindings[@]}" -eq 6',
  'test "${#pi_evidence_entries[@]}" -eq 36',
  'pi-runtime-pre-${pi_id}-${target_id}.json',
  'pi-node-pre-${pi_id}-${target_id}.json',
  'test ! -L "$evidence_file"',
  'archive="dist/mainframe-${RELEASE_VERSION}.tar.gz"',
  'pi_evidence="dist/mainframe-${RELEASE_VERSION}.pi-evidence.json"',
  '--version "$RELEASE_VERSION"',
  '--tag-ref-sha "$TAG_REF_SHA"',
  '--tag-commit-sha "$TAG_COMMIT"',
  'mapfile -t durable_pi_cell_names',
  'test "${#durable_pi_cell_names[@]}" -eq 6',
  'install -m 0644 "$source_cell" "$durable_cell"',
  '--cell-receipts-dir dist',
  "build-pi-release-evidence.py create",
  "build-pi-release-evidence.py verify",
  ".github/schemas/pi-release-evidence.schema.json",
  ".github/schemas/pi-cell-evidence.schema.json",
  "--cell-schema",
  '([.matrix[] | select(.compatibility.support == "unverified")] | length) == 4',
  'expected_pi_test_sha=',
  '"$expected_pi_test_sha"',
  %q!test "$(grep -Fxc '1..45' "$tap_file")" -eq 1!,
  %q!test "$(grep -Ec '^ok [0-9]+ ' "$tap_file" || true)" -eq 45!,
  '"$digest_file")" = "$archive_sha"',
  ".certifier_input_bundle.files | length",
  'expected_certifier_input_count="$(jq -er \'.files | length\'',
  '"$expected_certifier_input_count"'
]
required_fragments.each do |fragment|
  raise "missing release evidence fragment: #{fragment}" unless script.include?(fragment)
end
%w[archive checksum sbom formula manifest bundle pi_evidence].each do |name|
  raise "missing #{name} transfer hash output" unless script.include?("#{name}_sha256=%s")
end
puts "release build graph valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "release build graph valid" ]]
}

@test "release build binds Linux exact-candidate conformance to final archive bytes" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
job = workflow.fetch("jobs").fetch("release-build")
needs = Array(job.fetch("needs"))
raise "Linux conformance is not release-gated" unless
  needs.include?("stable-core-conformance-linux")

steps = job.fetch("steps")
names = steps.map { |step| step.fetch("name") }
download_name = "Download Linux exact-candidate conformance evidence"
download_index = names.index(download_name)
bind_index = names.index("Bind gate evidence to final release bytes")
raise "Linux conformance download or bind step missing" unless download_index && bind_index
raise "Linux conformance must be downloaded before binding" unless download_index < bind_index

download = steps.fetch(download_index)
raise "Linux conformance action pin drift" unless download.fetch("uses") ==
  "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"
expected_download = {
  "name" => "linux-exact-candidate-conformance",
  "path" => "gate-evidence/stable-core/linux"
}
raise "Linux conformance download contract drift" unless
  download.fetch("with") == expected_download

script = steps.fetch(bind_index).fetch("run")
required_fragments = [
  %q!linux_conformance_root="gate-evidence/stable-core/linux"!,
  %q!linux_candidate_checksum="$linux_conformance_root/${linux_archive_name}.sha256"!,
  %q!linux_candidate_manifest="$linux_conformance_root/mainframe-${linux_version}.candidate.json"!,
  %q!linux_conformance_log="$linux_conformance_root/stable-core-conformance.log"!,
  %q!linux_conformance_tap="$linux_conformance_root/stable-core-conformance.tap"!,
  %q!linux_broker_pocs="$linux_conformance_root/broker-pocs.txt"!,
  %q!linux_evidence_checksum="$linux_conformance_root/linux-exact-candidate-conformance.sha256"!,
  %q!test "${#linux_conformance_inventory[@]}" -eq 8!,
  %q!test "$(wc -l < "$linux_evidence_checksum" | tr -d '[:space:]')" -eq 7!,
  %q!test "${#linux_hashed_paths[@]}" -eq "${#linux_evidence_paths[@]}"!,
  %q!sha256sum -c "$(basename "$linux_evidence_checksum")"!,
  %q!test "$(awk 'NF == 2 {print $1}' "$linux_candidate_checksum")" = "$archive_sha"!,
  %q!.artifacts.archive.sha256 == $archive_sha!,
  %q!stable_core_conformance=PASS contracts=26 cases=28 adapters=cli,node,python,mcp,pi skipped=none!,
  %q!grep -Fxc '1..4' "$linux_conformance_tap"!,
  %q!grep -Ec '^ok [0-9]+ ' "$linux_conformance_tap"!,
  %q!if grep -Eq '^not ok ' "$linux_conformance_tap"; then!,
  %q!if grep -Fq '# skip ' "$linux_conformance_tap"; then!,
  %q!ERROR: Linux conformance TAP contains a failing test!,
  %q!ERROR: Linux conformance TAP contains a skipped test!,
  %q!min_arithmetic_payload=denied_without_execution!,
  %q!max_arithmetic_payload=denied_without_execution!,
  %q!signed_and_leading_zero_ranges=preserved!,
  %q!test "$(wc -l < "$linux_broker_pocs" | tr -d '[:space:]')" -eq 3!,
  %q!mapfile -t linux_shell_jsons!,
  %q!test "${#linux_shell_jsons[@]}" -eq 2!,
  %q!for shell_name in bash zsh; do!,
  %q!codex-Linux-x86_64-glibc-${shell_name}.json!,
  %q!.archive_sha256 == $archive_sha!
]
required_fragments.each do |fragment|
  raise "Linux conformance binding missing: #{fragment}" unless script.include?(fragment)
end
puts "Linux exact-candidate evidence binding valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "Linux exact-candidate evidence binding valid" ]]
}

@test "custom attestation is one exact four-subject predicate with pinned verification" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
steps = workflow.fetch("jobs").fetch("release-build").fetch("steps")
attest = steps.find { |step| step["name"] == "Attest release evidence predicate" }
raise "custom attestation step missing" unless attest
raise "custom attestation action pin drift" unless attest.fetch("uses") ==
  "actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d"
inputs = attest.fetch("with")
expected_subjects = [
  "dist/mainframe-${{ steps.version.outputs.version }}.tar.gz",
  "dist/mainframe-${{ steps.version.outputs.version }}.release-evidence.json",
  "dist/mainframe-${{ steps.version.outputs.version }}.release-evidence.tar.gz",
  "dist/mainframe-${{ steps.version.outputs.version }}.pi-evidence.json"
]
actual_subjects = inputs.fetch("subject-path").lines.map(&:strip).reject(&:empty?)
raise "custom attestation subject set drift" unless actual_subjects == expected_subjects
predicate_type = "https://github.com/gtwatts/mainframe/attestations/release-evidence/v1"
raise "custom predicate type drift" unless inputs.fetch("predicate-type") == predicate_type
raise "custom predicate path drift" unless inputs.fetch("predicate-path") == expected_subjects.fetch(1)

verify = steps.find { |step| step["name"] == "Verify published provenance attestation" }
script = verify.fetch("run")
[
  '--predicate-type "$predicate_type"',
  '--signer-workflow "$GITHUB_REPOSITORY/.github/workflows/test.yml"',
  '--signer-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-digest "${{ steps.version.outputs.tag_commit }}"',
  '--source-ref "$GITHUB_REF"',
  "--deny-self-hosted-runners",
  "--limit 100",
  "--format json",
  'evidence_run_id="$(jq -er \'.release.workflow.run_id\' "$manifest")"',
  'evidence_run_attempt="$(jq -er \'.release.workflow.run_attempt\' "$manifest")"',
  'test "$evidence_run_id" = "$GITHUB_RUN_ID"',
  'test "$evidence_run_attempt" = "$GITHUB_RUN_ATTEMPT"',
  'expected_release_invocation="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${evidence_run_id}/attempts/${evidence_run_attempt}"',
  '--arg expected_invocation "$expected_release_invocation"',
  '--arg expected_run_id "$evidence_run_id"',
  '--argjson expected_run_attempt "$evidence_run_attempt"',
  '--argjson expected_subjects "$expected_subjects"',
  ".verificationResult.statement.predicate == $manifest[0]",
  ".verificationResult.statement.predicate.release.workflow.run_id",
  ".verificationResult.statement.predicate.release.workflow.run_attempt",
  ".verificationResult.statement.subject | sort_by(.name)",
  ".verificationResult.signature.certificate.runInvocationURI",
  ".verificationResult.signature.certificate.runnerEnvironment"
].each do |fragment|
  raise "custom verification is missing: #{fragment}" unless script.include?(fragment)
end
puts "custom attestation contract valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "custom attestation contract valid" ]]
}

@test "publish transfer is hash-pinned and immutable publication is rerun-safe" {
    run ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
job = workflow.fetch("jobs").fetch("release-publish")
build_steps = workflow.fetch("jobs").fetch("release-build").fetch("steps")
expected_permissions = {
  "actions" => "read",
  "attestations" => "read",
  "contents" => "write"
}
raise "release-publish permissions drift" unless job.fetch("permissions") == expected_permissions
steps = job.fetch("steps")
transfer = build_steps.find { |step| step["name"] == "Transfer release assets to publish job" }
expected_transfer_paths = [
  "dist/mainframe-${{ steps.version.outputs.version }}.tar.gz",
  "dist/mainframe-${{ steps.version.outputs.version }}.tar.gz.sha256",
  "dist/mainframe-${{ steps.version.outputs.version }}.sbom.json",
  "dist/mainframe-${{ steps.version.outputs.version }}.release-evidence.json",
  "dist/mainframe-${{ steps.version.outputs.version }}.release-evidence.tar.gz",
  "dist/mainframe-${{ steps.version.outputs.version }}.pi-evidence.json",
  "dist/mainframe_mcp-${{ steps.version.outputs.version }}-py3-none-any.whl",
  "dist/mainframe_mcp-${{ steps.version.outputs.version }}.tar.gz",
  "dist/mainframe-mcp-candidate.sha256",
  "dist/pi-cell-fork-0.84.1-Darwin-arm64-none.json",
  "dist/pi-cell-fork-0.84.1-Darwin-x86_64-none.json",
  "dist/pi-cell-fork-0.84.1-Linux-x86_64-glibc.json",
  "dist/pi-cell-upstream-0.73.1-Darwin-arm64-none.json",
  "dist/pi-cell-upstream-0.73.1-Darwin-x86_64-none.json",
  "dist/pi-cell-upstream-0.73.1-Linux-x86_64-glibc.json",
  "dist/mainframe.rb"
]
actual_transfer_paths = transfer.fetch("with").fetch("path").lines.map(&:strip).reject(&:empty?)
raise "release transfer must contain exactly 16 immutable assets" unless
  actual_transfer_paths.length == 16
raise "release transfer asset inventory drift" unless actual_transfer_paths == expected_transfer_paths
raise "release transfer must fail on a missing asset" unless
  transfer.fetch("with").fetch("if-no-files-found") == "error"
reverify = steps.find { |step| step["name"] == "Reverify transferred archive" }
reverify_script = reverify.fetch("run")
expected_env = {
  "EXPECTED_ARCHIVE_SHA" => "${{ needs.release-build.outputs.release_archive_sha256 }}",
  "EXPECTED_CHECKSUM_SHA" => "${{ needs.release-build.outputs.release_checksum_sha256 }}",
  "EXPECTED_SBOM_SHA" => "${{ needs.release-build.outputs.release_sbom_sha256 }}",
  "EXPECTED_FORMULA_SHA" => "${{ needs.release-build.outputs.release_formula_sha256 }}",
  "EXPECTED_MANIFEST_SHA" => "${{ needs.release-build.outputs.release_evidence_manifest_sha256 }}",
  "EXPECTED_BUNDLE_SHA" => "${{ needs.release-build.outputs.release_evidence_bundle_sha256 }}",
  "EXPECTED_PI_EVIDENCE_SHA" => "${{ needs.release-build.outputs.release_pi_evidence_sha256 }}",
  "EXPECTED_MCP_WHEEL_SHA" => "${{ needs.release-build.outputs.release_mcp_wheel_sha256 }}",
  "EXPECTED_MCP_SDIST_SHA" => "${{ needs.release-build.outputs.release_mcp_sdist_sha256 }}",
  "EXPECTED_MCP_MANIFEST_SHA" => "${{ needs.release-build.outputs.release_mcp_manifest_sha256 }}"
}
expected_env.each do |key, value|
  raise "publish transfer env #{key} drift" unless reverify.fetch("env")[key] == value
  raise "publish transfer hash #{key} unused" unless reverify_script.include?(key)
end
raise "publish verify CLI missing" unless reverify_script.include?(
  "build-release-evidence.py verify"
)
raise "publish Pi verify CLI missing" unless reverify_script.include?(
  "build-pi-release-evidence.py verify"
)
[
  "umask 077",
  'candidate_root="$(mktemp -d',
  'trap cleanup_candidate EXIT',
  'candidate_manifest="$candidate_root/mainframe-${RELEASE_VERSION}.candidate.json"',
  "scripts/dev/verify-release-candidate.py",
  '--version "$RELEASE_VERSION"',
  '--archive "$archive"',
  '--checksum "$checksum"',
  '--sbom "$sbom"',
  '--formula "$formula"',
  '--manifest "$candidate_manifest"',
  'test -s "$candidate_manifest"',
  'pi_evidence="dist/mainframe-${RELEASE_VERSION}.pi-evidence.json"',
  'mcp_wheel="dist/mainframe_mcp-${RELEASE_VERSION}-py3-none-any.whl"',
  'mcp_sdist="dist/mainframe_mcp-${RELEASE_VERSION}.tar.gz"',
  'mcp_pair_manifest="dist/mainframe-mcp-candidate.sha256"',
  'MCP runtime-pair manifest record count is not exact',
  'MCP runtime-pair manifest order or syntax is invalid',
  'MCP runtime-pair digest mismatch',
  'f"{label} runtime binding mismatch"',
  'test ! -L "$pi_evidence"',
  '.github/schemas/pi-release-evidence.schema.json',
  '--contract .github/pi-evidence-contract.json',
  '--cell-receipts-dir dist',
  '--evidence "$pi_evidence"'
].each do |fragment|
  raise "pre-publish candidate verification missing: #{fragment}" unless
    reverify_script.include?(fragment)
end

publish = steps.find do |step|
  step["name"] == "Create complete draft, then publish or verify existing release"
end
raise "publish step id drift" unless publish.fetch("id") == "publish_release"
reverify_index = steps.index(reverify)
publish_index = steps.index(publish)
raise "strong candidate verification must precede release creation" unless
  reverify_index && publish_index && reverify_index < publish_index
publish_script = publish.fetch("run")
[
  'gh release view "$tag"',
  '.isDraft == false',
  '.isPrerelease == false',
  "entering immutable verification-only mode",
  "created=false",
  "created=true",
  'gh release create "$tag"',
  "--verify-tag",
  "--draft",
  "draft_asset_names=(",
  'test "${#draft_asset_names[@]}" -eq 16',
  '"repos/$GH_REPO/releases?per_page=100"',
  '.[] | select(.tag_name == $tag and .draft == true)',
  'test "${#draft_releases[@]}" -eq 1',
  'draft_metadata="${draft_releases[0]}"',
  '.tag_name == $tag and .draft == true and .prerelease == false',
  '{name: $name, digest: ("sha256:" + $sha)}',
  '[.assets[] | {name, digest}] | sort_by(.name)',
  "draft release asset names or digests are not exact",
  'draft_root="$(mktemp -d',
  'trap cleanup_draft_assets EXIT',
  'if length == 1 then .[0].id else error("asset id is not unique") end',
  '"repos/$GH_REPO/releases/assets/$asset_id" > "$remote_asset"',
  'test "${#downloaded_draft_assets[@]}" -eq 16',
  'cmp -- "dist/$asset_name" "$remote_asset"',
  'gh release edit "$tag" --draft=false'
].each do |fragment|
  raise "rerun-safe publish fragment missing: #{fragment}" unless publish_script.include?(fragment)
end

assets = [
  '"dist/mainframe-${RELEASE_VERSION}.tar.gz"',
  '"dist/mainframe-${RELEASE_VERSION}.tar.gz.sha256"',
  '"dist/mainframe-${RELEASE_VERSION}.sbom.json"',
  '"dist/mainframe-${RELEASE_VERSION}.release-evidence.json"',
  '"dist/mainframe-${RELEASE_VERSION}.release-evidence.tar.gz"',
  '"dist/mainframe-${RELEASE_VERSION}.pi-evidence.json"',
  '"dist/mainframe_mcp-${RELEASE_VERSION}-py3-none-any.whl"',
  '"dist/mainframe_mcp-${RELEASE_VERSION}.tar.gz"',
  '"dist/mainframe-mcp-candidate.sha256"',
  '"dist/pi-cell-fork-0.84.1-Darwin-arm64-none.json"',
  '"dist/pi-cell-fork-0.84.1-Darwin-x86_64-none.json"',
  '"dist/pi-cell-fork-0.84.1-Linux-x86_64-glibc.json"',
  '"dist/pi-cell-upstream-0.73.1-Darwin-arm64-none.json"',
  '"dist/pi-cell-upstream-0.73.1-Darwin-x86_64-none.json"',
  '"dist/pi-cell-upstream-0.73.1-Linux-x86_64-glibc.json"',
  '"dist/mainframe.rb"'
]
assets.each do |asset|
  raise "release create asset missing: #{asset}" unless publish_script.include?(asset)
end
create_index = publish_script.index('gh release create "$tag"')
download_draft_index = publish_script.index(
  '"repos/$GH_REPO/releases/assets/$asset_id" > "$remote_asset"'
)
publish_draft_index = publish_script.index('gh release edit "$tag" --draft=false')
raise "draft assets must be remotely verified before publication" unless
  create_index && download_draft_index && publish_draft_index &&
    create_index < download_draft_index && download_draft_index < publish_draft_index
raise "tag identity must be rechecked after draft verification" unless
  publish_script[download_draft_index...publish_draft_index].include?(
    "verify_tag_identity"
  )
raise "candidate validity manifest must never be a release asset" if
  publish_script.include?(".candidate.json")

final = steps.find { |step| step["name"] == "Verify immutable release and archive attestation" }
final_script = final.fetch("run")
raise "existing immutable release must not be pinned to a rerun receipt digest" if
  final.fetch("env").key?("EXPECTED_PI_EVIDENCE_SHA") ||
  final_script.include?("EXPECTED_PI_EVIDENCE_SHA")
raise "existing immutable release must not be pinned to rerun MCP digests" if
  %w[EXPECTED_MCP_WHEEL_SHA EXPECTED_MCP_SDIST_SHA
     EXPECTED_MCP_MANIFEST_SHA].any? do |name|
    final.fetch("env").key?(name) || final_script.include?(name)
  end
raise "released Pi attestation verification must not use the rerun identity" if
  final_script.include?('expected_pi_invocation="https://github.com/${GH_REPO}/actions/runs/${GITHUB_RUN_ID}')
[
  '.immutable',
  "immutable release asset inventory is not exact",
  '${{ steps.publish_release.outputs.created }}',
  'gh release download "$tag"',
  'for asset in',
  '"$archive"',
  '"$checksum"',
  '"$sbom"',
  '"$manifest"',
  '"$bundle"',
  '"$pi_evidence"',
  '"$mcp_wheel"',
  '"$mcp_sdist"',
  '"$mcp_pair_manifest"',
  '"$formula"',
  "umask 077",
  'candidate_root="$(mktemp -d',
  'trap cleanup_candidate EXIT',
  'candidate_manifest="$candidate_root/mainframe-${RELEASE_VERSION}.candidate.json"',
  "scripts/dev/verify-release-candidate.py",
  '--version "$RELEASE_VERSION"',
  '--archive "$archive"',
  '--checksum "$checksum"',
  '--sbom "$sbom"',
  '--formula "$formula"',
  '--manifest "$candidate_manifest"',
  'test -s "$candidate_manifest"',
  'gh release verify-asset "$tag" "$asset"',
  "build-release-evidence.py verify",
  "build-pi-release-evidence.py verify",
  'pi_evidence="$asset_root/mainframe-${RELEASE_VERSION}.pi-evidence.json"',
  '"mainframe-\($version).pi-evidence.json"',
  '--cell-receipts-dir "$asset_root"',
  '--evidence "$pi_evidence"',
  'expected_pi_invocation="https://github.com/${GH_REPO}/actions/runs/${pi_evidence_run_id}/attempts/${pi_evidence_run_attempt}"',
  'mcp_invocation_prefix="https://github.com/${GH_REPO}/actions/runs/${evidence_run_id}/attempts/"',
  '--argjson max_attempt "$evidence_run_attempt"',
  'expected_release_invocation="https://github.com/${GH_REPO}/actions/runs/${evidence_run_id}/attempts/${evidence_run_attempt}"',
  '.verificationResult.statement.predicate.release.workflow.run_id',
  '.verificationResult.statement.predicate.release.workflow.run_attempt',
  'mapfile -t released_pi_cell_names',
  'test "${#released_pi_cell_names[@]}" -eq 6',
  'for cell_name in "${released_pi_cell_names[@]}"; do',
  'gh attestation verify "$cell_receipt"',
  '--predicate-type https://slsa.dev/provenance/v1',
  '.verificationResult.statement.subject == [',
  '.verificationResult.statement.predicate.runDetails.metadata.invocationId ==',
  '.verificationResult.signature.certificate.runInvocationURI ==',
  '.verificationResult.signature.certificate.runnerEnvironment ==',
  '--arg pi_evidence_name "${pi_evidence##*/}"',
  '--predicate-type "$predicate_type"',
  '--signer-digest "$EXPECTED_TAG_COMMIT"',
  '--source-digest "$EXPECTED_TAG_COMMIT"',
  '--source-ref "$tag_ref"',
  "--deny-self-hosted-runners"
].each do |fragment|
  raise "immutable verification fragment missing: #{fragment}" unless final_script.include?(fragment)
end
expected_immutable_assets = [
  '"mainframe-\($version).tar.gz"',
  '"mainframe-\($version).tar.gz.sha256"',
  '"mainframe-\($version).sbom.json"',
  '"mainframe-\($version).release-evidence.json"',
  '"mainframe-\($version).release-evidence.tar.gz"',
  '"mainframe-\($version).pi-evidence.json"',
  '"mainframe_mcp-\($version)-py3-none-any.whl"',
  '"mainframe_mcp-\($version).tar.gz"',
  '"mainframe-mcp-candidate.sha256"',
  '"pi-cell-fork-0.84.1-Darwin-arm64-none.json"',
  '"pi-cell-fork-0.84.1-Darwin-x86_64-none.json"',
  '"pi-cell-fork-0.84.1-Linux-x86_64-glibc.json"',
  '"pi-cell-upstream-0.73.1-Darwin-arm64-none.json"',
  '"pi-cell-upstream-0.73.1-Darwin-x86_64-none.json"',
  '"pi-cell-upstream-0.73.1-Linux-x86_64-glibc.json"',
  '"mainframe.rb"'
]
raise "immutable release must contain exactly 16 assets" unless
  expected_immutable_assets.length == 16
expected_immutable_assets.each do |asset|
  expected_count = asset == '"mainframe-mcp-candidate.sha256"' ? 2 : 1
  raise "immutable release asset count drift: #{asset}" unless
    final_script.scan(asset).length == expected_count
end
%w[
  pi-cell-fork-0.84.1-Darwin-arm64-none.json
  pi-cell-fork-0.84.1-Darwin-x86_64-none.json
  pi-cell-fork-0.84.1-Linux-x86_64-glibc.json
  pi-cell-upstream-0.73.1-Darwin-arm64-none.json
  pi-cell-upstream-0.73.1-Darwin-x86_64-none.json
  pi-cell-upstream-0.73.1-Linux-x86_64-glibc.json
].each do |name|
  release_asset = %Q!"$asset_root/#{name}"!
  raise "durable Pi cell is not release-asset verified: #{name}" unless
    final_script.include?(release_asset)
end
download_index = final_script.index('gh release download "$tag"')
candidate_index = final_script.index("scripts/dev/verify-release-candidate.py")
durable_index = final_script.index('--cell-receipts-dir "$asset_root"')
cell_attestation_index = final_script.index('gh attestation verify "$cell_receipt"')
raise "immutable candidate verification must follow release asset selection" unless
  download_index && candidate_index && download_index < candidate_index
raise "released Pi receipt verification order is unsafe" unless
  durable_index && cell_attestation_index &&
    candidate_index < durable_index && durable_index < cell_attestation_index
puts "publish transfer and immutability contract valid"
RUBY
    [[ "$status" -eq 0 ]]
    [[ "$output" == "publish transfer and immutability contract valid" ]]
}

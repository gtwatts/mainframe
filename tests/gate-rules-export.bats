#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    BASH_BIN="${MAINFRAME_BASH:-/opt/homebrew/bin/bash}"
    [[ -x "$BASH_BIN" ]] || BASH_BIN="$(command -v bash)"
}

@test "gate export preserves every canonical rule in source order" {
    run env PYTHONDONTWRITEBYTECODE=1 python3 - "$PROJECT_ROOT" <<'PY'
import importlib.util
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "export_gate_rules", root / "scripts" / "export-gate-rules.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
rules = module.parse_rules((root / "lib" / "agent_safety.sh").read_text())

expected = [
    "unsupported-control-byte", "dynamic-executable-word", "shell-eval",
    "dynamic-shell-expansion", "inline-git-alias",
    "recursive-force-rm", "sudo-rm", "filesystem-format",
    "dd-raw-disk-write", "diskutil-erase", "fork-bomb",
    "raw-device-redirect", "rm-recursive", "chmod-recursive-777",
    "chown-recursive", "git-clean-destructive", "git-reset-hard",
    "docker-system-prune", "kubectl-delete", "terraform-destroy",
    "s3-recursive-delete", "find-delete", "xargs-rm-pipeline",
    "rsync-delete", "opaque-pipe-to-shell", "git-push-mirror",
    "kill-all-processes", "find-exec-shell", "python-rmtree",
    "perl-unlink", "ruby-rmrf", "node-rmsync",
    "mainframe-project-memory-initialization",
    "mainframe-project-memory-close",
    "mainframe-explicit-confirmation", "mainframe-runtime-mutation",
    "git-push-force",
    "truncate-resize", "git-worktree-reset", "killall", "npm-publish",
    "crontab-remove", "launchctl-mutate",
]
actual = [rule["id"] for rule in rules]
assert len(actual) == 43, actual
assert len(set(actual)) == 43, actual
assert actual == expected, actual
print("43 canonical rules preserved in source order")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "43 canonical rules preserved in source order" ]]
}

@test "checked gate export declares its normalizer and complete input contract" {
    run python3 "$PROJECT_ROOT/scripts/export-gate-rules.py" --check
    [[ "$status" -eq 0 ]]

    run python3 - "$PROJECT_ROOT/security/gate-rules.json" \
        "$PROJECT_ROOT/security/gate-normalizer.mjs" <<'PY'
import hashlib
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    document = json.load(handle)
with open(sys.argv[2], "rb") as handle:
    normalizer_digest = hashlib.sha256(handle.read()).hexdigest()

normalizer = document["normalizer"]
assert normalizer["contract"] == "executable-marker-v1"
assert normalizer["module"] == "security/gate-normalizer.mjs"
assert normalizer["normalize_export"] == "normalizeGateCommand"
assert normalizer["classify_export"] == "classifyGateCommand"
assert normalizer["marker"] == "\x1e"
assert normalizer["rule_input_field"] == "input"
assert normalizer["inputs"] == ["raw", "raw-inert", "normalized", "normalized-both", "flat"]
assert normalizer["sha256"] == normalizer_digest

rules = document["rules"]
ids = [rule["id"] for rule in rules]
by_id = {rule["id"]: rule for rule in rules}
assert len(ids) == 43
assert len(set(ids)) == 43
assert all(rule["input"] in normalizer["inputs"] for rule in rules)
assert all("${marker}" not in rule["js"] for rule in rules)
assert by_id["fork-bomb"]["js"].startswith(r"\x1e")
assert r"[^\x1e]*" in by_id["git-clean-destructive"]["js"]
assert ids[0] == "unsupported-control-byte"
assert ids[1] == "dynamic-executable-word"
assert ids[2] == "shell-eval"
assert ids[3] == "dynamic-shell-expansion"
assert ids[4] == "inline-git-alias"
assert ids[5] == "recursive-force-rm"
assert ids[10] == "fork-bomb"
assert ids[11] == "raw-device-redirect"
assert ids[12] == "rm-recursive"
print("generated ruleset and normalizer contract are complete")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "generated ruleset and normalizer contract are complete" ]]

    run node --input-type=module - "$PROJECT_ROOT/security/gate-rules.json" \
        "$PROJECT_ROOT/security/gate-normalizer.mjs" <<'JS'
import fs from "node:fs";
import {pathToFileURL} from "node:url";

const rules = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).rules;
const {classifyGateCommand, decodeGateWord, resolveGateCommand} =
  await import(pathToFileURL(process.argv[3]).href);
if (resolveGateCommand('printf "$toString"', {}) !== 'printf ""') {
  throw new Error("variable resolution must ignore inherited object properties");
}
if (decodeGateWord(String.raw`$'\562\555'`) !== "rm") {
  throw new Error("ANSI-C octal escapes must retain Bash byte semantics");
}
const cases = [
  ["rm -v -rf /tmp/x", "critical", "recursive-force-rm"],
  ["rm --verbose --recursive --force /tmp/x", "critical", "recursive-force-rm"],
  ["rm $'\\x2d\\x72\\x66' /tmp/x", "critical", "recursive-force-rm"],
  ["env -S 'rm -rf /tmp/x'", "critical", "recursive-force-rm"],
  ["git -c alias.wipe='reset --hard' wipe", "critical", "inline-git-alias"],
  ["cat x > '/dev/sda'", "critical", "raw-device-redirect"],
  ["rm -v -r /tmp/x", "high", "rm-recursive"],
  ['git "reset" "--hard"', "high", "git-reset-hard"],
  ['op=reset; git "$op" --hard', "high", "git-reset-hard"],
  ['terraform "destroy"', "high", "terraform-destroy"],
  ['npm "publish"', "medium", "npm-publish"],
  ['mainframe pi install --yes', "high", "mainframe-explicit-confirmation"],
  ['/opt/mainframe/bin/mainframe pi remove --yes', "high", "mainframe-explicit-confirmation"],
  ['command mainframe setup --host pi --yes', "high", "mainframe-explicit-confirmation"],
  ['action=install; mainframe pi "$action" --yes', "high", "mainframe-explicit-confirmation"],
  ['mainframe update', "high", "mainframe-runtime-mutation"],
  ['mainframe upgrade --version 10.2.1 --confirm-agents-stopped', "high", "mainframe-runtime-mutation"],
  ['mainframe uninstall', "high", "mainframe-runtime-mutation"],
  ['brew uninstall gtwatts/mainframe/mainframe', "high", "mainframe-runtime-mutation"],
  ['mainframe awm project ensure --project . --discover-root', "high", "mainframe-project-memory-initialization"],
  ['awm_project_ensure .', "high", "mainframe-project-memory-initialization"],
  ['mainframe awm init project --namespace projects', "high", "mainframe-project-memory-initialization"],
  ['awm_init project --namespace=projects', "high", "mainframe-project-memory-initialization"],
  ['mainframe awm project close --project . --discover-root', "high", "mainframe-project-memory-close"],
  ['mainframe pi status', "low", "none"],
  ['mainframe pi doctor --json', "low", "none"],
  ['mainframe pi install --dry-run', "low", "none"],
  ['mainframe upgrade --version 10.2.1 --dry-run', "low", "none"],
  ['mainframe uninstall --dry-run', "low", "none"],
  ['mainframe awm project status --project . --discover-root', "low", "none"],
  ['mainframe awm project checkpoint --project . key value', "low", "none"],
  ["printf '%s' 'mainframe pi install --yes'", "low", "none"],
  ["printf '%s' 'mainframe awm project ensure --project .'", "low", "none"],
  ['git "$op" --hard', "high", "git-reset-hard", {op: "reset"}],
  ["rm -- --recursive --force /tmp/x", "low", "none"],
  ["git commit -m 'git reset --hard'", "low", "none"],
  ["printf '%s' ':(){ :|:& };:'", "low", "none"],
  ["printf '%s' '> /dev/sda'", "low", "none"],
  ["printf %s \\> /dev/sda", "low", "none"],
  // Heredoc bodies are data, not commands; shell-fed bodies stay gated.
  ["cat > /tmp/x.ts <<'EOF'\n/**\n * doc\n */\nEOF", "low", "none"],
  ["cat <<'EOF'\n$(rm -rf /tmp/x)\nEOF", "low", "none"],
  ["cat <<EOF\n$(rm -rf /tmp/x)\nEOF", "critical", "dynamic-shell-expansion"],
  ["bash <<'EOF'\nrm -rf /tmp/x\nEOF", "critical", "recursive-force-rm"],
  ["cat <<'EOF' | bash\nrm -rf /tmp/x\nEOF", "critical", "recursive-force-rm"],
  ["ssh host <<'EOF'\nrm -rf /tmp/x\nEOF", "critical", "recursive-force-rm"],
  ["cat <<-'EOF'\n\t/**\n\tEOF", "low", "none"],
];
for (const [command, expectedTier, expectedId, environment] of cases) {
  const match = classifyGateCommand(command, rules, environment);
  if (match.tier !== expectedTier || match.id !== expectedId) {
    throw new Error(`${command}: expected ${expectedTier}/${expectedId}, got ${match.tier}/${match.id}`);
  }
}
console.log("normalizer-backed gate parity preserved")
JS

    [[ "$status" -eq 0 ]]
    [[ "$output" == "normalizer-backed gate parity preserved" ]]
}

@test "gate verification and help are read-only" {
    local export_file="$PROJECT_ROOT/security/gate-rules.json"
    local normalizer_file="$PROJECT_ROOT/security/gate-normalizer.mjs"
    local before after_verify after_help
    before="$(shasum -a 256 "$export_file" "$normalizer_file")"

    run env PYTHONDONTWRITEBYTECODE=1 \
        python3 "$PROJECT_ROOT/scripts/export-gate-rules.py" --verify
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"verify: 183 corpus cases identical across bash + JS"* ]]
    after_verify="$(shasum -a 256 "$export_file" "$normalizer_file")"
    [[ "$after_verify" == "$before" ]]

    run env PYTHONDONTWRITEBYTECODE=1 \
        python3 "$PROJECT_ROOT/scripts/export-gate-rules.py" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == Usage:* ]]
    after_help="$(shasum -a 256 "$export_file" "$normalizer_file")"
    [[ "$after_help" == "$before" ]]
}

@test "canonical release payload includes the gate export and normalizer exactly once" {
    run "$BASH_BIN" -c '
      source "$1"
      mainframe_release_payload_files "$2"
    ' _ "$PROJECT_ROOT/scripts/dev/release-payload.sh" "$PROJECT_ROOT"

    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s\n' "$output" | grep -Fxc 'security/gate-rules.json')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -Fxc 'security/gate-normalizer.mjs')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -Fxc 'package.json')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -Fxc 'lib/pi.sh')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -Fxc 'skills/pi/extensions/mainframe.ts')" -eq 1 ]]
}

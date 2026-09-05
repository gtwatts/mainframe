#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-pi-package.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    NPM_BIN="$(command -v npm 2>/dev/null || true)"
    NODE_BIN="$(command -v node 2>/dev/null || true)"
    PYTHON_BIN="$(command -v python3 2>/dev/null || true)"

    [[ -n "$NPM_BIN" && -x "$NPM_BIN" ]] || skip "npm is required"
    [[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]] || skip "python3 is required"

    NPM_HOME="$TEST_ROOT/npm-home"
    NPM_CACHE="$TEST_ROOT/npm-cache"
    PACK_DIR="$TEST_ROOT/packs"
    EXTRACT_DIR="$TEST_ROOT/extracted"
    XDG_STATE_HOME="$TEST_ROOT/state"
    mkdir -p "$NPM_HOME" "$NPM_CACHE" "$PACK_DIR" "$EXTRACT_DIR"
    mkdir -m 0700 "$XDG_STATE_HOME"
    export XDG_STATE_HOME
}

teardown() {
    rm -rf -- "$TEST_ROOT"
}

find_pi_0842() {
    local candidate version

    for candidate in \
        "${MAINFRAME_PI_BIN:-}" \
        /opt/homebrew/bin/pi \
        /usr/local/bin/pi \
        /home/linuxbrew/.linuxbrew/bin/pi \
        "$HOME/.bun/bin/pi"
    do
        [[ -n "$candidate" && "$candidate" == /* && -x "$candidate" ]] || continue
        version="$("$candidate" --version 2>/dev/null || true)"
        if [[ "$version" == 0.84.2 ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

npm_pack() {
    (
        cd "$PROJECT_ROOT" || exit 1
        env \
            HOME="$NPM_HOME" \
            npm_config_cache="$NPM_CACHE" \
            npm_config_userconfig=/dev/null \
            npm_config_ignore_scripts=true \
            npm_config_audit=false \
            npm_config_fund=false \
            npm_config_offline=true \
            npm_config_update_notifier=false \
            NO_UPDATE_NOTIFIER=1 \
            "$NPM_BIN" pack \
                --json \
                --ignore-scripts \
                --offline \
                --loglevel=silent \
                "$@"
    )
}

extract_pack() {
    local report="$1" filename

    filename="$($PYTHON_BIN - "$report" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert isinstance(document, list) and len(document) == 1
print(document[0]["filename"])
PY
)" || return 1
    [[ "$filename" == "gtwatts-mainframe-pi-"*.tgz ]] || return 1
    tar -xzf "$PACK_DIR/$filename" -C "$EXTRACT_DIR" || return 1
    PACK_ROOT="$EXTRACT_DIR/package"
    [[ -d "$PACK_ROOT" ]]
}

@test "offline npm dry-run contains only the bounded Pi runtime" {
    local report="$TEST_ROOT/dry-run.json"

    run npm_pack --dry-run
    [[ "$status" -eq 0 ]]
    printf '%s\n' "$output" > "$report"

    run "$PYTHON_BIN" - \
        "$PROJECT_ROOT/package.json" \
        "$PROJECT_ROOT/INVOCATION_INDEX.json" \
        "$PROJECT_ROOT/FUNCTIONS.json" \
        "$report" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
index_path = pathlib.Path(sys.argv[2])
functions_path = pathlib.Path(sys.argv[3])
report_path = pathlib.Path(sys.argv[4])

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
expected_allowlist = [
    "LICENSE",
    "README.md",
    "VERSION",
    "FUNCTIONS.json",
    "INVOCATION_INDEX.json",
    "MANIFEST.json",
    "bin/mainframe",
    "control_plane/mainframe-control-plane",
    "control_plane/mainframe_control_plane/*.py",
    "config/invocation-policy.json",
    "config/pi-compatibility.json",
    "config/semantic-trust-policy.json",
    "config/stable-core.json",
    "hooks/agent-gateway.sh",
    "lib/**/*.sh",
    "lib/runtime-closure.generated.bash",
    "security/gate-normalizer.mjs",
    "security/gate-rules.json",
    "skills/pi/SKILL.md",
    "skills/pi/extensions/mainframe.ts",
]
assert manifest.get("files") == expected_allowlist, manifest.get("files")

reports = json.loads(report_path.read_text(encoding="utf-8"))
assert isinstance(reports, list) and len(reports) == 1, reports
report = reports[0]
files = report.get("files")
assert isinstance(files, list) and files, report
paths = {record["path"] for record in files}
assert len(paths) == len(files), "npm pack emitted duplicate paths"

required = {
    "LICENSE",
    "README.md",
    "VERSION",
    "FUNCTIONS.json",
    "INVOCATION_INDEX.json",
    "MANIFEST.json",
    "package.json",
    "bin/mainframe",
    "control_plane/mainframe-control-plane",
    "control_plane/mainframe_control_plane/__init__.py",
    "control_plane/mainframe_control_plane/cli.py",
    "control_plane/mainframe_control_plane/coding.py",
    "control_plane/mainframe_control_plane/contracts.py",
    "control_plane/mainframe_control_plane/durability.py",
    "control_plane/mainframe_control_plane/errors.py",
    "control_plane/mainframe_control_plane/executor.py",
    "control_plane/mainframe_control_plane/kernel.py",
    "control_plane/mainframe_control_plane/memory.py",
    "control_plane/mainframe_control_plane/memory_executor.py",
    "control_plane/mainframe_control_plane/memory_transient.py",
    "control_plane/mainframe_control_plane/memory_worker.py",
    "control_plane/mainframe_control_plane/transient.py",
    "control_plane/mainframe_control_plane/worker.py",
    "config/invocation-policy.json",
    "config/pi-compatibility.json",
    "config/semantic-trust-policy.json",
    "config/stable-core.json",
    "hooks/agent-gateway.sh",
    "security/gate-normalizer.mjs",
    "security/gate-rules.json",
    "skills/pi/SKILL.md",
    "skills/pi/extensions/mainframe.ts",
}
missing = sorted(required - paths)
assert not missing, f"required Pi runtime files are missing: {missing}"

invocation_index = json.loads(index_path.read_text(encoding="utf-8"))
owner_files = {record["file"] for record in invocation_index["modules"].values()}
missing_owners = sorted(owner_files - paths)
assert not missing_owners, f"broker owner libraries are missing: {missing_owners}"

function_registry = json.loads(functions_path.read_text(encoding="utf-8"))
registry_files = {record["file"] for record in function_registry["libraries"].values()}
missing_registry_files = sorted(registry_files - paths)
assert not missing_registry_files, f"registry libraries are missing: {missing_registry_files}"

allowed_roots = {
    "LICENSE",
    "README.md",
    "VERSION",
    "FUNCTIONS.json",
    "INVOCATION_INDEX.json",
    "MANIFEST.json",
    "package.json",
    "bin",
    "control_plane",
    "config",
    "hooks",
    "lib",
    "security",
    "skills",
}
unexpected_roots = sorted({path.split("/", 1)[0] for path in paths} - allowed_roots)
assert not unexpected_roots, f"unexpected package roots: {unexpected_roots}"

assert {path for path in paths if path.startswith("bin/")} == {"bin/mainframe"}
assert {path for path in paths if path.startswith("control_plane/")} == {
    "control_plane/mainframe-control-plane",
    "control_plane/mainframe_control_plane/__init__.py",
    "control_plane/mainframe_control_plane/cli.py",
    "control_plane/mainframe_control_plane/coding.py",
    "control_plane/mainframe_control_plane/contracts.py",
    "control_plane/mainframe_control_plane/durability.py",
    "control_plane/mainframe_control_plane/errors.py",
    "control_plane/mainframe_control_plane/executor.py",
    "control_plane/mainframe_control_plane/kernel.py",
    "control_plane/mainframe_control_plane/memory.py",
    "control_plane/mainframe_control_plane/memory_executor.py",
    "control_plane/mainframe_control_plane/memory_transient.py",
    "control_plane/mainframe_control_plane/memory_worker.py",
    "control_plane/mainframe_control_plane/transient.py",
    "control_plane/mainframe_control_plane/worker.py",
}
assert {path for path in paths if path.startswith("config/")} == {
    "config/invocation-policy.json",
    "config/pi-compatibility.json",
    "config/semantic-trust-policy.json",
    "config/stable-core.json",
}
# npm-packlist automatically carries ancestor README files when an explicitly
# allowlisted descendant is packed. Keep that mandatory behavior exact.
assert {path for path in paths if path.startswith("hooks/")} == {
    "hooks/README.md",
    "hooks/agent-gateway.sh",
}
assert {path for path in paths if path.startswith("security/")} == {
    "security/gate-normalizer.mjs",
    "security/gate-rules.json",
}
assert {path for path in paths if path.startswith("skills/")} == {
    "skills/README.md",
    "skills/pi/SKILL.md",
    "skills/pi/extensions/mainframe.ts",
}
packed_libraries = {path for path in paths if path.startswith("lib/")}
source_libraries = {
    str(path.relative_to(manifest_path.parent))
    for path in (manifest_path.parent / "lib").rglob("*.sh")
}
source_libraries.add("lib/runtime-closure.generated.bash")
assert packed_libraries == source_libraries, {
    "missing": sorted(source_libraries - packed_libraries),
    "extra": sorted(packed_libraries - source_libraries),
}

for forbidden in (".pi/", ".github/", "benchmarks/", "bindings/", "demos/", "docs/", "evals/", "lsp/", "mcp/", "packaging/", "scripts/", "tests/"):
    assert not any(path.startswith(forbidden) for path in paths), forbidden

assert report["entryCount"] == len(files)
assert paths == required | source_libraries | {"hooks/README.md", "skills/README.md"}
assert report["entryCount"] <= 241, report["entryCount"]
assert report["size"] <= 10_000_000, report["size"]
assert report["unpackedSize"] <= 20_000_000, report["unpackedSize"]
print(json.dumps({
    "entryCount": report["entryCount"],
    "size": report["size"],
    "unpackedSize": report["unpackedSize"],
}, sort_keys=True))
PY
    [[ "$status" -eq 0 ]]
}

@test "packed payload loads hand-in-glove through Pi 0.84.2" {
    local pi_bin report="$TEST_ROOT/pack.json"
    pi_bin="$(find_pi_0842)" || skip "Pi 0.84.2 is not installed"
    [[ -n "$NODE_BIN" && -x "$NODE_BIN" ]] || skip "Node.js is required"

    run npm_pack --pack-destination "$PACK_DIR"
    [[ "$status" -eq 0 ]]
    printf '%s\n' "$output" > "$report"
    extract_pack "$report"

    mkdir -p "$TEST_ROOT/pi-home" "$TEST_ROOT/pi-agent"
    run env \
        HOME="$TEST_ROOT/pi-home" \
        PI_CODING_AGENT_DIR="$TEST_ROOT/pi-agent" \
        "$NODE_BIN" --input-type=module - "$PACK_ROOT" "$pi_bin" <<'JS'
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const root = realpathSync(process.argv[2]);
const piCli = realpathSync(process.argv[3]);
process.argv[1] = piCli;

const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const version = readFileSync(join(root, "VERSION"), "utf8").trim();
if (manifest.name !== "@gtwatts/mainframe-pi" || manifest.version !== version) {
  throw new Error(`unexpected packed manifest: ${JSON.stringify(manifest)}`);
}
const loaderPath = join(dirname(piCli), "core", "extensions", "loader.js");
if (!existsSync(loaderPath)) throw new Error(`Pi extension loader not found: ${loaderPath}`);
const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(root, "skills", "pi", "extensions", "mainframe.ts");
const { extensions, errors, runtime } = await loadExtensions([extensionPath], root);
if (errors.length) throw new Error(`Pi loader errors: ${JSON.stringify(errors)}`);
if (extensions.length !== 1) throw new Error(`expected one extension, got ${extensions.length}`);

const extension = extensions[0];
const packageToolSourceInfo = {
  path: extensionPath,
  source: root,
  scope: "user",
  origin: "package",
  baseDir: root,
};
runtime.getAllTools = () => [...extension.tools.values()].map(({ definition }) => ({
  name: definition.name,
  sourceInfo: { ...packageToolSourceInfo },
}));
runtime.getActiveTools = () => [...extension.tools.keys()];
const expectedTools = [
  "mainframe_awm",
  "mainframe_bash_safety_check",
  "mainframe_exec",
  "mainframe_help",
  "mainframe_install_commands",
  "mainframe_search",
  "mainframe_status",
];
const tools = [...extension.tools.keys()].sort();
if (JSON.stringify(tools) !== JSON.stringify(expectedTools)) {
  throw new Error(`unexpected packed tool surface: ${JSON.stringify(tools)}`);
}
if (JSON.stringify([...extension.commands.keys()]) !== JSON.stringify(["mainframe"])) {
  throw new Error("packed /mainframe command is missing");
}

const ctx = { cwd: root, ui: {} };
const statusTool = extension.tools.get("mainframe_status")?.definition;
const searchTool = extension.tools.get("mainframe_search")?.definition;
const safetyTool = extension.tools.get("mainframe_bash_safety_check")?.definition;
const execTool = extension.tools.get("mainframe_exec")?.definition;
if (!statusTool || !searchTool || !safetyTool || !execTool) {
  throw new Error("packed Pi control plane is incomplete");
}

const status = await statusTool.execute("packed-status", {}, undefined, undefined, ctx);
if (status?.details?.root !== root || status?.details?.installed !== true ||
    status?.details?.registryFound !== true || status?.details?.bashSafetyGate?.enabled !== true ||
    status?.details?.piRuntime?.runtime?.tools?.length !== 7) {
  throw new Error(`packed status failed: ${JSON.stringify(status)}`);
}
const search = await searchTool.execute(
  "packed-search",
  { query: "json object", limit: 10 },
  undefined,
  undefined,
  ctx,
);
if (!search?.details?.matches?.some((record) => record.function === "json_object")) {
  throw new Error(`packed registry search failed: ${JSON.stringify(search)}`);
}
const packedAgent = await searchTool.execute(
  "packed-search-agent",
  { query: "agent register", limit: 10 },
  undefined,
  undefined,
  ctx,
);
const packedAgentMatches = packedAgent?.details?.matches?.filter((record) => record.function === "agent_register") || [];
if (packedAgent?.details?.purpose !== "script" || packedAgentMatches.length !== 1 ||
    packedAgentMatches[0].owner !== "agent_comm" ||
    packedAgentMatches[0].canonicalId !== "mf:std:agent_comm:agent_register") {
  throw new Error(`packed canonical registry owner failed: ${JSON.stringify(packedAgent)}`);
}
const packedDirectory = await searchTool.execute(
  "packed-search-directory",
  { query: "create directory", limit: 10 },
  undefined,
  undefined,
  ctx,
);
const packedDirectoryNames = packedDirectory?.details?.matches?.map((record) => record.function) || [];
if (packedDirectoryNames.indexOf("ensure_dir") < 0 ||
    packedDirectoryNames.indexOf("ensure_dir") >= packedDirectoryNames.indexOf("dir_create")) {
  throw new Error(`packed safety-aware ranking failed: ${JSON.stringify(packedDirectory)}`);
}
const packedExample = await searchTool.execute(
  "packed-search-example",
  { query: "localhost:3000", limit: 10 },
  undefined,
  undefined,
  ctx,
);
const packedParseUrl = packedExample?.details?.matches?.find((record) => record.function === "parse_url");
if (!packedParseUrl?.examples?.includes('parse_url "http://localhost:3000/api/v1"') ||
    packedExample.details.matches.some((record) => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(record.function))) {
  throw new Error(`packed example/canonical-name search failed: ${JSON.stringify(packedExample)}`);
}
const safety = await safetyTool.execute(
  "packed-safety",
  { command: "printf pi-packed-safe" },
  undefined,
  undefined,
  ctx,
);
if (safety?.details?.safety?.blocked !== false) {
  throw new Error(`packed gate rejected a safe command: ${JSON.stringify(safety)}`);
}
const executed = await execTool.execute(
  "packed-exec",
  { functionName: "json_object", args: ["tool=pi", "packed:bool=true"] },
  undefined,
  undefined,
  ctx,
);
if (executed?.details?.result?.code !== 0 ||
    !executed?.details?.result?.stdout?.includes('"packed":true') ||
    executed?.details?.broker?.status !== "success" ||
    executed?.details?.controlPlane?.status !== "completed" ||
    executed?.details?.controlPlane?.outcome !== "succeeded" ||
    executed?.details?.controlPlane?.resultAvailable !== true ||
    !/^client-pi-[0-9a-f]{32}$/.test(executed?.details?.controlPlane?.clientCorrelationId || "") ||
    !/^run-[0-9a-f]{32}$/.test(executed?.details?.controlPlane?.runId || "") ||
    !/^call-[0-9a-f]{32}$/.test(executed?.details?.controlPlane?.callId || "") ||
    !/^decision-[0-9a-f]{32}$/.test(executed?.details?.controlPlane?.decisionId || "") ||
    !/^evidence-[0-9a-f]{32}$/.test(executed?.details?.controlPlane?.evidenceId || "") ||
    executed?.details?.controlPlane?.brokerReceipt?.audit_id !== executed?.details?.broker?.auditId) {
  throw new Error(`packed broker execution failed: ${JSON.stringify(executed)}`);
}

console.log("packed MAINFRAME loads through Pi 0.84.2 with all seven tools, gate, registry, and broker");
JS
    [[ "$status" -eq 0 ]]
    [[ "$output" == "packed MAINFRAME loads through Pi 0.84.2 with all seven tools, gate, registry, and broker" ]]
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-pi-compatibility.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
}

teardown() {
    rm -rf -- "$TEST_ROOT"
}

find_pi() {
    local candidate

    if [[ -n "${MAINFRAME_PI_BIN:-}" ]]; then
        [[ "$MAINFRAME_PI_BIN" == /* && -x "$MAINFRAME_PI_BIN" ]] || return 1
        printf '%s\n' "$MAINFRAME_PI_BIN"
        return 0
    fi

    for candidate in \
        /opt/homebrew/bin/pi \
        /usr/local/bin/pi \
        /home/linuxbrew/.linuxbrew/bin/pi \
        "$HOME/.bun/bin/pi"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v pi 2>/dev/null || return 1
}

find_node() {
    local candidate

    if [[ -n "${MAINFRAME_PI_NODE_BIN:-}" ]]; then
        [[ "$MAINFRAME_PI_NODE_BIN" == /* && -x "$MAINFRAME_PI_NODE_BIN" ]] || return 1
        printf '%s\n' "$MAINFRAME_PI_NODE_BIN"
        return 0
    fi

    for candidate in \
        /opt/homebrew/bin/node \
        /usr/local/bin/node \
        /home/linuxbrew/.linuxbrew/bin/node \
        /usr/bin/node
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v node 2>/dev/null || return 1
}

@test "real Pi loader rejects malformed compatibility manifests before READY" {
    local pi_bin node_bin loader_home loader_agent
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"
    loader_home="$TEST_ROOT/loader-home"
    loader_agent="$TEST_ROOT/loader-agent"
    mkdir -p "$loader_home" "$loader_agent"

    run env \
        HOME="$loader_home" \
        PI_CODING_AGENT_DIR="$loader_agent" \
        "$node_bin" --input-type=module - "$PROJECT_ROOT" "$pi_bin" <<'JS'
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const projectRoot = process.argv[2];
const piBin = process.argv[3];
const piCli = realpathSync(piBin);
const piPackageRoot = dirname(dirname(piCli));
const piManifest = JSON.parse(readFileSync(join(piPackageRoot, "package.json"), "utf8"));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function clone(value) {
  return structuredClone(value);
}

function platformTuple() {
  const os = process.platform === "darwin" ? "Darwin" : process.platform === "linux" ? "Linux" : process.platform;
  const arch = process.arch === "x64" ? "x86_64" : process.arch === "arm64" ? "arm64" : process.arch;
  let libc = os === "Darwin" ? "none" : "unknown";
  if (os === "Linux") {
    try {
      if (process.report?.getReport?.()?.header?.glibcVersionRuntime) libc = "glibc";
    } catch {}
  }
  return `${os}-${arch}-${libc}`;
}

const runtimeRoot = join(process.env.HOME, ".mainframe");
const compatibilityPath = join(runtimeRoot, "config", "pi-compatibility.json");
mkdirSync(join(runtimeRoot, "bin"), { recursive: true });
mkdirSync(join(runtimeRoot, "config"), { recursive: true });
mkdirSync(join(runtimeRoot, "lib"), { recursive: true });
mkdirSync(join(runtimeRoot, "security"), { recursive: true });
mkdirSync(join(runtimeRoot, "skills", "pi", "extensions"), { recursive: true });
writeFileSync(join(runtimeRoot, "lib", "common.sh"), "# compatibility test fixture\n");
copyFileSync(join(projectRoot, "security", "gate-rules.json"), join(runtimeRoot, "security", "gate-rules.json"));
copyFileSync(join(projectRoot, "security", "gate-normalizer.mjs"), join(runtimeRoot, "security", "gate-normalizer.mjs"));
copyFileSync(
  join(projectRoot, "skills", "pi", "extensions", "mainframe.ts"),
  join(runtimeRoot, "skills", "pi", "extensions", "mainframe.ts"),
);

const mainframeVersion = readFileSync(join(projectRoot, "VERSION"), "utf8").trim();
writeFileSync(join(runtimeRoot, "VERSION"), `${mainframeVersion}\n`);
const cliPath = join(runtimeRoot, "bin", "mainframe");
writeFileSync(cliPath, `#!/bin/sh
if [ "\${1-}" = pi ] && [ "\${2-}" = status ] && [ "\${3-}" = --json ]; then
  printf '{"state":"ready","package_active":true,"package_source":"%s","mainframe_root":"%s"}\\n' "$MAINFRAME_ROOT" "$MAINFRAME_ROOT"
  exit 0
fi
exit 64
`);
chmodSync(cliPath, 0o755);

const baseline = JSON.parse(readFileSync(join(projectRoot, "config", "pi-compatibility.json"), "utf8"));
const fixtureIntegrity = baseline.certifications.find((record) =>
  record.package === piManifest.name && record.version === piManifest.version)?.npm_integrity ||
  baseline.certifications[0]?.npm_integrity;
assert(typeof fixtureIntegrity === "string", "canonical fixture has no package integrity");
baseline.certifications = [{
  id: "pi-current-platform-full",
  mainframe_version: mainframeVersion,
  package: piManifest.name,
  version: piManifest.version,
  npm_integrity: fixtureIntegrity,
  platforms: [platformTuple()],
  support: "certified",
  profile: "full",
  evidence_date: "2026-08-09",
  evidence: ["tests/pi_compatibility_manifest.bats"],
  capabilities: {
    local_package_discovery: "verified",
    prompt_hook: "verified",
    seven_tool_surface: "verified",
    agent_bash_gate: "verified",
    tui_user_bash_gate: "verified",
    rpc_user_bash_gate: "verified",
    bash_and_zsh_callers: "verified",
  },
  limitations: [],
}];

function writeCompatibility(document) {
  writeFileSync(compatibilityPath, `${JSON.stringify(document, null, 2)}\n`);
}

process.argv[1] = piCli;
const loaderPath = join(dirname(piCli), "core", "extensions", "loader.js");
assert(existsSync(loaderPath), `Pi extension loader not found: ${loaderPath}`);
const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(runtimeRoot, "skills", "pi", "extensions", "mainframe.ts");
const { extensions, errors, runtime } = await loadExtensions([extensionPath], runtimeRoot);
assert(errors.length === 0, `Pi loader errors: ${JSON.stringify(errors)}`);
assert(extensions.length === 1, `expected one extension, got ${extensions.length}`);
const packageToolSourceInfo = {
  path: extensionPath,
  source: runtimeRoot,
  scope: "user",
  origin: "package",
  baseDir: runtimeRoot,
};
runtime.getAllTools = () => [...extensions[0].tools.values()].map(({ definition }) => ({
  name: definition.name,
  sourceInfo: { ...packageToolSourceInfo },
}));
runtime.getActiveTools = () => [...extensions[0].tools.keys()];
const statusTool = extensions[0].tools.get("mainframe_status")?.definition;
assert(statusTool, "mainframe_status definition missing");

async function inspect(document, label) {
  writeCompatibility(document);
  const result = await statusTool.execute(
    `compatibility-${label}`,
    { root: runtimeRoot },
    undefined,
    undefined,
    { cwd: projectRoot, ui: {} },
  );
  const text = result?.content?.map((item) => item?.text || "").join("\n") || "";
  return { result, text, runtime: result?.details?.piRuntime };
}

const control = await inspect(baseline, "valid-control");
assert(control.runtime?.compatibility?.manifestReady === true,
  `valid control manifest was rejected: ${control.text}`);
assert(control.runtime?.ready === true && control.runtime?.state === "ready",
  `valid control fixture did not establish READY: ${control.text}`);
assert(control.text.includes("MAINFRAME + Pi: READY"),
  `valid control did not render READY: ${control.text}`);

const promptHandlers = extensions[0].handlers.get("before_agent_start") || [];
assert(promptHandlers.length === 1, `expected one prompt hook, got ${promptHandlers.length}`);
const promptBase = "PROMPT_PREFIX_SENTINEL\n<project-context/>";
writeCompatibility(baseline);
const readyPrompt = await promptHandlers[0]({
  type: "before_agent_start",
  systemPrompt: promptBase,
  systemPromptOptions: {},
}, { cwd: projectRoot });
const readyText = readyPrompt?.systemPrompt || "";
assert(readyText.startsWith(promptBase), "READY hook did not preserve the original prompt prefix");
assert((readyText.match(/<mainframe-pi-runtime version="1">/g) || []).length === 1,
  "READY hook did not append exactly one canonical block");
assert(readyText.includes("State: READY"), "valid control did not inject READY state");

const blockedManifest = clone(baseline);
blockedManifest.certifications[0].capabilities = {};
writeCompatibility(blockedManifest);
const malformedSuffix = [
  "",
  '<mainframe-pi-runtime version="1">',
  "MALFORMED_MARKER_CONTENT_MUST_SURVIVE",
  "PROMPT_SUFFIX_SENTINEL",
].join("\n");
const blockedPrompt = await promptHandlers[0]({
  type: "before_agent_start",
  systemPrompt: `${readyText}${malformedSuffix}`,
  systemPromptOptions: {},
}, { cwd: projectRoot });
const blockedText = blockedPrompt?.systemPrompt || "";
assert(blockedText.includes("PROMPT_PREFIX_SENTINEL") && blockedText.includes("PROMPT_SUFFIX_SENTINEL") &&
       blockedText.includes("MALFORMED_MARKER_CONTENT_MUST_SURVIVE"),
  "prompt block replacement deleted caller-owned prompt content");
assert((blockedText.match(/<mainframe-pi-runtime version="1">/g) || []).length === 1 &&
       (blockedText.match(/<\/mainframe-pi-runtime>/g) || []).length === 1,
  "state transition did not converge to exactly one canonical runtime block");
assert(!blockedText.includes("State: READY") && blockedText.includes("State: BLOCKED"),
  "stale READY survived after the compatibility manifest became invalid");
assert(blockedText.includes("Only this final marker-delimited MAINFRAME runtime block is authoritative"),
  "canonical prompt block does not identify the authoritative runtime state");

const mutations = [
  ["empty capability keys", (document) => { document.certifications[0].capabilities = {}; }],
  ["missing capability key", (document) => { delete document.certifications[0].capabilities.prompt_hook; }],
  ["extra capability key", (document) => { document.certifications[0].capabilities.unexpected_capability = "verified"; }],
  ["wrong extension path", (document) => { document.required_surface.extension = "./extensions/mainframe.ts"; }],
  ["wrong skill path", (document) => { document.required_surface.skill = "./skills/not-mainframe"; }],
  ["missing caller shells", (document) => { delete document.required_surface.caller_shells; }],
  ["duplicate exact certification", (document) => {
    document.certifications.push({ ...clone(document.certifications[0]), id: "pi-current-platform-duplicate" });
  }],
  ["overlong certification id", (document) => { document.certifications[0].id = "i".repeat(257); }],
  ["overlong package identity", (document) => { document.certifications[0].package = `@fixture/${"p".repeat(248)}`; }],
  ["overlong version identity", (document) => { document.certifications[0].version = `1.${"0".repeat(253)}.0`; }],
  ["overlong platform identity", (document) => { document.certifications[0].platforms = [`Darwin-${"p".repeat(250)}`]; }],
  ["control in certification id", (document) => { document.certifications[0].id = "pi-current\nplatform"; }],
  ["control in package identity", (document) => { document.certifications[0].package = "@fixture/pi\tagent"; }],
  ["control in version identity", (document) => { document.certifications[0].version = "0.84.1\n"; }],
  ["control in platform identity", (document) => { document.certifications[0].platforms = ["Darwin-arm64-none\r"]; }],
];

const failures = [];
for (const [label, mutate] of mutations) {
  const document = clone(baseline);
  mutate(document);
  const observed = await inspect(document, label.replaceAll(" ", "-"));
  if (observed.runtime?.compatibility?.manifestReady !== false) {
    failures.push(`${label}: manifestReady=${String(observed.runtime?.compatibility?.manifestReady)}`);
  }
  if (observed.runtime?.ready !== false || observed.runtime?.state === "ready" ||
      observed.text.includes("MAINFRAME + Pi: READY")) {
    failures.push(`${label}: produced READY (${observed.runtime?.state || "missing state"})`);
  }
}

assert(failures.length === 0,
  `malformed compatibility manifests were not rejected:\n${failures.join("\n")}`);
console.log(`real Pi loader rejected ${mutations.length} malformed compatibility manifests`);
JS

    [[ "$status" -eq 0 ]]
    [[ "$output" == "real Pi loader rejected 15 malformed compatibility manifests" ]]
}

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-pi.XXXXXX")"
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

@test "Pi package manifest exposes the first-party extension and skill" {
    run python3 - \
        "$PROJECT_ROOT/package.json" \
        "$PROJECT_ROOT/config/pi-compatibility.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
document = json.loads(path.read_text(encoding="utf-8"))
assert document["name"] == "@gtwatts/mainframe-pi"
assert document["version"] == pathlib.Path(path.parent / "VERSION").read_text().strip()
assert document["peerDependencies"] == {"typebox": "*"}
assert document["pi"] == {
    "extensions": ["./skills/pi/extensions/mainframe.ts"],
    "skills": ["./skills/pi"],
}
compatibility = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert compatibility["schema_version"] == 1
assert compatibility["integration"] == document["name"]
assert compatibility["mainframe_version"] == document["version"]
assert compatibility["unknown_policy"] == {"support": "unverified", "ready": False}
assert compatibility["required_surface"]["tools"] == [
    "mainframe_awm",
    "mainframe_bash_safety_check",
    "mainframe_exec",
    "mainframe_help",
    "mainframe_install_commands",
    "mainframe_search",
    "mainframe_status",
]
assert compatibility["required_surface"]["hooks"] == ["before_agent_start", "tool_call", "user_bash"]
records = compatibility["certifications"]
keys = [
    (record["mainframe_version"], record["package"], record["version"], platform)
    for record in records
    for platform in record["platforms"]
]
assert len(keys) == len(set(keys)), keys
assert all(record["mainframe_version"] == document["version"] for record in records)
current = next(record for record in records if record["package"] == "@earendil-works/pi-coding-agent")
legacy = next(record for record in records if record["package"] == "@mariozechner/pi-coding-agent")
assert current["version"] == "0.84.2" and current["support"] == "certified"
assert all(value == "verified" for value in current["capabilities"].values())
assert legacy["version"] == "0.73.1" and legacy["support"] == "limited"
assert legacy["capabilities"]["rpc_user_bash_gate"] == "not-observable"
assert legacy["limitations"]
for record in records:
    assert record["npm_integrity"].startswith("sha512-")
print("native Pi package contract is canonical")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "native Pi package contract is canonical" ]]
}

@test "Pi loader preserves the system prompt and exposes exactly the supported surface" {
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
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const piBin = process.argv[3];
const loaderPath = join(dirname(realpathSync(piBin)), "core", "extensions", "loader.js");
if (!existsSync(loaderPath)) throw new Error(`Pi extension loader not found: ${loaderPath}`);
const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(root, "skills", "pi", "extensions", "mainframe.ts");
const poisonMarker = join(process.env.HOME, "bash-env-executed");
const poisonEnv = join(process.env.HOME, "bash-env-poison.sh");
writeFileSync(poisonEnv, `printf poison > ${JSON.stringify(poisonMarker)}\n`, { mode: 0o600 });
const forbiddenStartupVariables = [
  "BASH_ENV",
  "ENV",
  "BASH_LOADABLES_PATH",
  "NODE_OPTIONS",
  "PYTHONPATH",
  "RUBYOPT",
  "BASH_FUNC_mainframe_poison%%",
  "LD_PRELOAD",
  "DYLD_INSERT_LIBRARIES",
];
for (const key of forbiddenStartupVariables) process.env[key] = poisonEnv;
const { extensions, errors } = await loadExtensions([extensionPath], root);
if (errors.length) throw new Error(JSON.stringify(errors));
if (extensions.length !== 1) throw new Error(`expected one extension, got ${extensions.length}`);
for (const key of forbiddenStartupVariables) {
  if (Object.hasOwn(process.env, key)) throw new Error(`Pi extension retained inherited shell-loader variable ${key}`);
}
if (existsSync(poisonMarker)) throw new Error("BASH_ENV executed while the Pi extension was loading");
const extension = extensions[0];
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
  throw new Error(`unexpected tools: ${JSON.stringify(tools)}`);
}
if (JSON.stringify([...extension.commands.keys()]) !== JSON.stringify(["mainframe"])) {
  throw new Error("native /mainframe command missing");
}
const installTool = extension.tools.get("mainframe_install_commands")?.definition;
if (!installTool) throw new Error("mainframe_install_commands definition missing");
const installResult = await installTool.execute("loader-install", {}, undefined, undefined, { cwd: root, ui: {} });
const installText = installResult?.content?.map((item) => item?.text || "").join("\n") || "";
if (!installText.includes("mainframe pi install --dry-run") ||
	    !installText.includes("/mainframe doctor")) {
  throw new Error(`canonical Pi migration guidance missing: ${installText}`);
}
if (installText.includes("mainframe pi install --yes") ||
    /(^|\n)pi install\s/.test(installText) || installText.includes("--mode rpc")) {
  throw new Error(`legacy or hanging Pi install guidance returned: ${installText}`);
}
const statusTool = extension.tools.get("mainframe_status")?.definition;
if (!statusTool) throw new Error("mainframe_status definition missing");
const statusResult = await statusTool.execute("loader-status", {}, undefined, undefined, { cwd: root, ui: {} });
const statusText = statusResult?.content?.map((item) => item?.text || "").join("\n") || "";
if (!statusText.includes("MAINFRAME + Pi: COMPATIBILITY_UNVERIFIED") ||
    statusResult?.details?.piRuntime?.ready !== false ||
    !statusText.includes("tools=0/7 effective") ||
    statusResult?.details?.piRuntime?.runtime?.tools?.length !== 0 ||
    statusResult?.details?.piRuntime?.runtime?.expectedTools?.length !== 7 ||
    statusResult?.details?.piRuntime?.runtime?.toolProof?.status !== "api-unavailable") {
  throw new Error(`mainframe_status made a false live-readiness claim: ${statusText}`);
}

const handlers = extension.handlers.get("before_agent_start") || [];
if (handlers.length !== 1) throw new Error(`expected one prompt hook, got ${handlers.length}`);
const base = "BASE_SYSTEM_PROMPT\n<project-context/>";
const promptResult = await handlers[0]({
  type: "before_agent_start",
  prompt: "smoke",
  images: [],
  systemPrompt: base,
  systemPromptOptions: {},
}, {});
if (!promptResult?.systemPrompt?.includes(base)) throw new Error("Pi system prompt was replaced");
if (!promptResult.systemPrompt.includes("# MAINFRAME")) throw new Error("MAINFRAME preamble missing");
const badgeUpdates = [];
const badgedPromptResult = await handlers[0]({
  type: "before_agent_start",
  prompt: "badge-smoke",
  images: [],
  systemPrompt: base,
  systemPromptOptions: {},
}, {
  cwd: root,
  ui: { setStatus: (key, text) => badgeUpdates.push({ key, text }) },
});
const promptState = badgedPromptResult?.systemPrompt?.match(/\nState: ([A-Z_]+)\n/)?.[1];
const expectedBadges = {
  READY: "MF READY",
  LIMITED: "MF LIMITED",
  COMPATIBILITY_UNVERIFIED: "MF UNVERIFIED",
  PROJECT_OVERRIDE: "MF PROJECT_OVERRIDE",
  SETUP_REQUIRED: "MF SETUP_REQUIRED",
  RELOAD_REQUIRED: "MF RELOAD_REQUIRED",
  BLOCKED: "MF BLOCKED",
};
if (!promptState || badgeUpdates.length !== 1 || badgeUpdates[0]?.key !== "mainframe" ||
    badgeUpdates[0]?.text !== expectedBadges[promptState]) {
  throw new Error(`startup readiness badge drifted from the prompt state: ${JSON.stringify({ promptState, badgeUpdates })}`);
}
const throwingUiPromptResult = await handlers[0]({
  type: "before_agent_start",
  prompt: "non-tui-smoke",
  images: [],
  systemPrompt: base,
  systemPromptOptions: {},
}, {
  cwd: root,
  ui: { setStatus: () => { throw new Error("status UI unavailable"); } },
});
if (!throwingUiPromptResult?.systemPrompt?.includes("# MAINFRAME")) {
  throw new Error("an unavailable status UI broke the startup hook");
}

const toolCallHandlers = extension.handlers.get("tool_call") || [];
if (toolCallHandlers.length !== 1) throw new Error(`expected one tool-call hook, got ${toolCallHandlers.length}`);
const safeEvent = { type: "tool_call", toolName: "bash", input: { command: "printf pi-safe" } };
const safeResult = await toolCallHandlers[0](safeEvent, { cwd: root });
if (safeResult?.block) throw new Error(`safe command blocked: ${safeResult.reason}`);
if (!safeEvent.input.command.includes("pi-mainframe-auto-source")) throw new Error("safe bash was not wrapped");
process.env.BASH_ENV = poisonEnv;
process.env.ENV = poisonEnv;
process.env.BASH_LOADABLES_PATH = poisonEnv;
process.env["BASH_FUNC_mainframe_poison%%"] = "() { printf poison; }";
process.env.DYLD_INSERT_LIBRARIES = poisonEnv;
const agentEnvEvent = { type: "tool_call", toolName: "bash", input: { command: "printf pi-agent-env-safe" } };
const agentEnvResult = await toolCallHandlers[0](agentEnvEvent, { cwd: root });
if (agentEnvResult?.block) throw new Error(`agent environment regression was blocked: ${agentEnvResult.reason}`);
for (const key of ["BASH_ENV", "ENV", "BASH_LOADABLES_PATH", "BASH_FUNC_mainframe_poison%%", "DYLD_INSERT_LIBRARIES"]) {
  if (Object.hasOwn(process.env, key)) throw new Error(`agent Bash retained reintroduced shell-loader variable ${key}`);
}
const piIndexPath = join(dirname(realpathSync(piBin)), "index.js");
const { createBashToolDefinition } = await import(pathToFileURL(piIndexPath).href);
const actualPiBash = createBashToolDefinition(root);
const agentEnvExecution = await actualPiBash.execute(
  "loader-agent-env",
  { command: agentEnvEvent.input.command, timeout: 15 },
  undefined,
  undefined,
  undefined,
);
const agentEnvOutput = agentEnvExecution?.content?.map((item) => item?.text || "").join("") || "";
if (agentEnvOutput !== "pi-agent-env-safe" || existsSync(poisonMarker)) {
  throw new Error(`current Pi agent Bash inherited BASH_ENV: ${JSON.stringify({ agentEnvOutput, poison: existsSync(poisonMarker) })}`);
}
const requiredCallerShells = ["/bin/bash", "/bin/zsh"];
const missingCallerShells = requiredCallerShells.filter((shell) => !existsSync(shell));
if (process.env.MAINFRAME_PI_REQUIRE_BOTH_SHELLS === "1" && missingCallerShells.length) {
  throw new Error(`required caller shells are missing: ${missingCallerShells.join(", ")}`);
}
const callerShells = requiredCallerShells.filter(existsSync);
for (const shell of callerShells) {
  const executed = spawnSync(shell, ["-c", safeEvent.input.command], {
    cwd: root,
    env: { ...process.env, SHELL: shell },
    encoding: "utf8",
    timeout: 15_000,
  });
  if (executed.status !== 0 || executed.stdout !== "pi-safe") {
    throw new Error(`wrapped agent bash failed from ${shell}: ${JSON.stringify({ status: executed.status, stdout: executed.stdout, stderr: executed.stderr })}`);
  }
}
const literalText = "rm -rf /tmp/mainframe-pi-literal-only";
const literalEvent = { type: "tool_call", toolName: "bash", input: { command: `printf '%s' '${literalText}'` } };
const literalResult = await toolCallHandlers[0](literalEvent, { cwd: root });
if (literalResult?.block) throw new Error(`quoted destructive text was blocked: ${literalResult.reason}`);
for (const shell of callerShells) {
  const executed = spawnSync(shell, ["-c", literalEvent.input.command], {
    cwd: root,
    env: { ...process.env, SHELL: shell },
    encoding: "utf8",
    timeout: 15_000,
  });
  if (executed.status !== 0 || executed.stdout !== literalText) {
    throw new Error(`quoted-text false-positive regression from ${shell}: ${JSON.stringify({ status: executed.status, stdout: executed.stdout, stderr: executed.stderr })}`);
  }
}
const injectedMarker = { type: "tool_call", toolName: "bash", input: { command: "printf marker-text # pi-mainframe-auto-source" } };
await toolCallHandlers[0](injectedMarker, { cwd: root });
if (injectedMarker.input.command === "printf marker-text # pi-mainframe-auto-source" ||
    !/^# pi-mainframe-auto-source:[a-f0-9]{64}\n/.test(injectedMarker.input.command)) {
  throw new Error("a caller-supplied wrapper marker bypassed protected Bash");
}
const injectedOptOut = { type: "tool_call", toolName: "bash", input: { command: "MAINFRAME_NO_AUTO_SOURCE=1 printf opt-out-text" } };
await toolCallHandlers[0](injectedOptOut, { cwd: root });
if (injectedOptOut.input.command === "MAINFRAME_NO_AUTO_SOURCE=1 printf opt-out-text" ||
    !/^# pi-mainframe-auto-source:[a-f0-9]{64}\n/.test(injectedOptOut.input.command)) {
  throw new Error("a caller-supplied opt-out bypassed protected Bash");
}
const blockedEvent = { type: "tool_call", toolName: "bash", input: { command: "op=rm; $op -r -f /tmp/mainframe-pi-never-run" } };
const blockedResult = await toolCallHandlers[0](blockedEvent, { cwd: root });
if (!blockedResult?.block || !blockedResult.reason?.includes("dynamic-executable-word")) {
  throw new Error(`obfuscated destructive command was not blocked: ${JSON.stringify(blockedResult)}`);
}
for (const command of [
  "mainframe pi install --yes",
  "command mainframe pi --yes remove",
  "mainframe pi restore --backup-id .mainframe-pi-backup-20260812T162516Z.Ab12Cd --yes",
  "mainframe setup --yes --host=pi",
  "mainframe pi in'stall' --y\\es",
  "m=mainframe; $m pi remove --yes",
  "m=mainframe; $m pi res'tore' --backup-id .mainframe-pi-backup-20260812T162516Z.Ab12Cd --y\\es",
]) {
  const lifecycleEvent = { type: "tool_call", toolName: "bash", input: { command } };
  const lifecycleResult = await toolCallHandlers[0](lifecycleEvent, { cwd: root });
  if (!lifecycleResult?.block || !lifecycleResult.reason?.includes("pi-lifecycle-human-confirmation-required")) {
    throw new Error(`Pi lifecycle mutation was not blocked: ${JSON.stringify({ command, lifecycleResult })}`);
  }
}
for (const [command, reason] of [
  ["mainframe awm project ensure --project . --discover-root", "project-memory-initialization-human-confirmation-required"],
  ["awm_project_ensure .", "project-memory-initialization-human-confirmation-required"],
  ["mainframe awm project context --project . capacity", "project-memory-specialized-tool-required"],
  ["mainframe awm project session --project .", "project-memory-specialized-tool-required"],
  ["awm_project_status .", "project-memory-specialized-tool-required"],
  ["mainframe awm get --session abcdef123456 project-secret", "awm-specialized-tool-required"],
  ["awm_resume abcdef123456; awm_get project-secret", "awm-specialized-tool-required"],
  ["mainframe update", "mainframe-runtime-mutation-human-terminal-required"],
  ["mainframe upgrade --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"],
  ["m=mainframe; $m up'grade' --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"],
  ["mainframe shell repair --shell all --yes", "mainframe-shell-lifecycle-human-terminal-required"],
  ["m=mainframe; $m sh'ell' repair --shell all --y\\es", "mainframe-shell-lifecycle-human-terminal-required"],
  ["brew upgrade mainframe", "homebrew-mainframe-mutation-human-terminal-required"],
  ["b=brew; $b up'grade' gtwatts/mainframe/mainframe", "homebrew-mainframe-mutation-human-terminal-required"],
  ["/opt/homebrew/bin/brew uninstall --formula mainframe", "homebrew-mainframe-mutation-human-terminal-required"],
]) {
  const mutationEvent = { type: "tool_call", toolName: "bash", input: { command } };
  const mutationResult = await toolCallHandlers[0](mutationEvent, { cwd: root });
  if (!mutationResult?.block || !mutationResult.reason?.includes(reason)) {
    throw new Error(`agent runtime mutation was not blocked: ${JSON.stringify({ command, mutationResult })}`);
  }
}
for (const command of [
  "mainframe upgrade --dry-run",
  "mainframe uninstall --dry-run",
  "mainframe version",
  "mainframe pi status",
  "mainframe pi doctor --json",
  "mainframe shell status --shell all",
  "mainframe shell repair --shell all --dry-run",
  "brew info mainframe",
  "brew list mainframe",
]) {
  const readOnlyEvent = { type: "tool_call", toolName: "bash", input: { command } };
  const readOnlyResult = await toolCallHandlers[0](readOnlyEvent, { cwd: root });
  if (readOnlyResult?.block) throw new Error(`read-only Mainframe command was blocked: ${JSON.stringify({ command, readOnlyResult })}`);
}
const lifecycleLiteral = { type: "tool_call", toolName: "bash", input: { command: "printf '%s' 'mainframe pi install --yes'" } };
const lifecycleLiteralResult = await toolCallHandlers[0](lifecycleLiteral, { cwd: root });
if (lifecycleLiteralResult?.block) throw new Error(`quoted Pi lifecycle text was blocked: ${lifecycleLiteralResult.reason}`);
const mainframeCommand = extension.commands.get("mainframe");
if (!mainframeCommand?.handler) throw new Error("native /mainframe classify handler missing");
async function classifyNotice(command) {
  const notices = [];
  await mainframeCommand.handler(`classify ${command}`, {
    cwd: root,
    ui: { notify: (message, level) => notices.push({ message, level }) },
  });
  return notices;
}
const blockedClassify = await classifyNotice("mainframe upgrade --confirm-agents-stopped");
if (!blockedClassify.some(({ message }) => message.includes("blocked") && message.includes("mainframe-runtime-mutation-human-terminal-required"))) {
  throw new Error(`/mainframe classify missed runtime mutation: ${JSON.stringify(blockedClassify)}`);
}
const shellRepairClassify = await classifyNotice("mainframe shell repair --shell all --yes");
if (!shellRepairClassify.some(({ message }) => message.includes("blocked") && message.includes("mainframe-shell-lifecycle-human-terminal-required"))) {
  throw new Error(`/mainframe classify missed shell repair mutation: ${JSON.stringify(shellRepairClassify)}`);
}
const projectInitClassify = await classifyNotice("mainframe awm project ensure --project . --discover-root");
if (!projectInitClassify.some(({ message }) => message.includes("blocked") && message.includes("project-memory-initialization-human-confirmation-required"))) {
  throw new Error(`/mainframe classify missed project-memory initialization: ${JSON.stringify(projectInitClassify)}`);
}
const dryRunClassify = await classifyNotice("mainframe upgrade --dry-run");
if (!dryRunClassify.some(({ message }) => message.includes("allowed"))) {
  throw new Error(`/mainframe classify blocked upgrade dry-run: ${JSON.stringify(dryRunClassify)}`);
}
const uninstallDryRunClassify = await classifyNotice("mainframe uninstall --dry-run");
if (!uninstallDryRunClassify.some(({ message }) => message.includes("allowed"))) {
  throw new Error(`/mainframe classify blocked uninstall dry-run: ${JSON.stringify(uninstallDryRunClassify)}`);
}
for (const command of [
  "mainframe shell status --shell all",
  "mainframe shell repair --shell all --dry-run",
]) {
  const notices = await classifyNotice(command);
  if (!notices.some(({ message }) => message.includes("allowed"))) {
    throw new Error(`/mainframe classify blocked a read-only shell command: ${JSON.stringify({ command, notices })}`);
  }
}
const userBashHandlers = extension.handlers.get("user_bash") || [];
if (userBashHandlers.length !== 1) throw new Error(`expected one user-bash hook, got ${userBashHandlers.length}`);
for (const shell of callerShells) {
  process.env.SHELL = shell;
  const safeUserBash = await userBashHandlers[0]({
    type: "user_bash",
    command: "declare -F json_object >/dev/null && printf pi-user-bash-safe",
    excludeFromContext: false,
    cwd: root,
  }, { cwd: root });
  if (!safeUserBash?.operations?.exec) throw new Error(`user_bash operations missing for ${shell}`);
  let safeOutput = "";
  const safeExecution = await safeUserBash.operations.exec(
    "declare -F json_object >/dev/null && printf pi-user-bash-safe",
    root,
    {
      onData: (chunk) => { safeOutput += chunk.toString(); },
      timeout: 15,
      env: {
        ...process.env,
        BASH_ENV: poisonEnv,
        ENV: poisonEnv,
        BASH_LOADABLES_PATH: poisonEnv,
        "BASH_FUNC_mainframe_poison%%": "() { printf poison; }",
        DYLD_INSERT_LIBRARIES: poisonEnv,
        SHELL: shell,
      },
    },
  );
  if (safeExecution.exitCode !== 0 || safeOutput !== "pi-user-bash-safe" || existsSync(poisonMarker)) {
    throw new Error(`TUI user_bash safe environment failed from ${shell}: ${JSON.stringify({ safeExecution, safeOutput, poison: existsSync(poisonMarker) })}`);
  }

  const blockedCommand = "op=rm; $op -r -f /tmp/mainframe-pi-never-run";
  const blockedUserBash = await userBashHandlers[0]({
    type: "user_bash",
    command: blockedCommand,
    excludeFromContext: false,
    cwd: root,
  }, { cwd: root });
  let blockedOutput = "";
  const blockedExecution = await blockedUserBash.operations.exec(blockedCommand, root, {
    onData: (chunk) => { blockedOutput += chunk.toString(); },
    timeout: 15,
    env: { ...process.env, SHELL: shell },
  });
  if (blockedExecution.exitCode !== 126 || !blockedOutput.includes("dynamic-executable-word")) {
    throw new Error(`TUI user_bash destructive gate failed from ${shell}: ${JSON.stringify({ blockedExecution, blockedOutput })}`);
  }

  for (const [lifecycleCommand, lifecycleReason] of [
    ["mainframe pi remove --yes", "pi-lifecycle-human-confirmation-required"],
    ["mainframe pi restore --backup-id .mainframe-pi-backup-20260812T162516Z.Ab12Cd --yes", "pi-lifecycle-human-confirmation-required"],
    ["mainframe shell repair --shell all --yes", "mainframe-shell-lifecycle-human-terminal-required"],
  ]) {
    const lifecycleUserBash = await userBashHandlers[0]({
      type: "user_bash",
      command: lifecycleCommand,
      excludeFromContext: false,
      cwd: root,
    }, { cwd: root });
    let lifecycleOutput = "";
    const lifecycleExecution = await lifecycleUserBash.operations.exec(lifecycleCommand, root, {
      onData: (chunk) => { lifecycleOutput += chunk.toString(); },
      timeout: 15,
      env: { ...process.env, SHELL: shell },
    });
    if (lifecycleExecution.exitCode !== 126 || !lifecycleOutput.includes(lifecycleReason)) {
      throw new Error(`TUI user_bash Pi lifecycle gate failed from ${shell}: ${JSON.stringify({ lifecycleCommand, lifecycleExecution, lifecycleOutput })}`);
    }
  }

  for (const readOnlyCommand of [
    "mainframe shell status --shell all",
    "mainframe shell repair --shell all --dry-run",
  ]) {
    const readOnlyUserBash = await userBashHandlers[0]({
      type: "user_bash",
      command: readOnlyCommand,
      excludeFromContext: false,
      cwd: root,
    }, { cwd: root });
    let readOnlyOutput = "";
    const readOnlyExecution = await readOnlyUserBash.operations.exec(readOnlyCommand, root, {
      onData: (chunk) => { readOnlyOutput += chunk.toString(); },
      timeout: 15,
      env: { ...process.env, SHELL: shell },
    });
    if (readOnlyExecution.exitCode === 126 || readOnlyOutput.includes("mainframe-shell-lifecycle-human-terminal-required")) {
      throw new Error(`TUI user_bash blocked a read-only shell command from ${shell}: ${JSON.stringify({ readOnlyCommand, readOnlyExecution, readOnlyOutput })}`);
    }
  }

  for (const [command, reason] of [
    ["mainframe awm project ensure --project . --discover-root", "project-memory-initialization-human-confirmation-required"],
    ["awm_project_ensure .", "project-memory-initialization-human-confirmation-required"],
    ["mainframe awm project context --project . capacity", "project-memory-specialized-tool-required"],
    ["mainframe awm project session --project .", "project-memory-specialized-tool-required"],
    ["awm_project_status .", "project-memory-specialized-tool-required"],
    ["mainframe awm get --session abcdef123456 project-secret", "awm-specialized-tool-required"],
    ["awm_resume abcdef123456; awm_get project-secret", "awm-specialized-tool-required"],
    ["mainframe update", "mainframe-runtime-mutation-human-terminal-required"],
    ["mainframe upgrade --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"],
    ["m=mainframe; $m up'grade' --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"],
    ["brew upgrade mainframe", "homebrew-mainframe-mutation-human-terminal-required"],
    ["b=brew; $b un'install' gtwatts/mainframe/mainframe", "homebrew-mainframe-mutation-human-terminal-required"],
  ]) {
    const mutationUserBash = await userBashHandlers[0]({
      type: "user_bash",
      command,
      excludeFromContext: false,
      cwd: root,
    }, { cwd: root });
    let mutationOutput = "";
    const mutationExecution = await mutationUserBash.operations.exec(command, root, {
      onData: (chunk) => { mutationOutput += chunk.toString(); },
      timeout: 15,
      env: { ...process.env, BASH_ENV: poisonEnv, ENV: poisonEnv, SHELL: shell },
    });
    if (mutationExecution.exitCode !== 126 || !mutationOutput.includes(reason) || existsSync(poisonMarker)) {
      throw new Error(`TUI user_bash runtime mutation escaped from ${shell}: ${JSON.stringify({ command, mutationExecution, mutationOutput, poison: existsSync(poisonMarker) })}`);
    }
  }
}
for (const profile of [".bashrc", ".bash_profile", ".bash_login", ".profile", ".zshrc"]) {
  if (existsSync(join(process.env.HOME, profile))) {
    throw new Error(`read-only shell lifecycle command created ${profile}`);
  }
}
const auditPath = join(process.env.PI_CODING_AGENT_DIR, ".mainframe-pi", "bash-audit.jsonl");
const auditRecords = readFileSync(auditPath, "utf8").trim().split("\n").map((line) => JSON.parse(line));
if (!auditRecords.length || auditRecords.some((record) => "command" in record || !/^[a-f0-9]{64}$/.test(record.command_sha256))) {
  throw new Error(`Pi audit leaked raw command text or omitted a digest: ${JSON.stringify(auditRecords)}`);
}
if ((lstatSync(auditPath).mode & 0o077) !== 0 || (lstatSync(dirname(auditPath)).mode & 0o077) !== 0) {
  throw new Error("Pi audit file or directory is not private");
}
if (existsSync(join(process.env.HOME, ".pi"))) {
  throw new Error("Pi audit ignored PI_CODING_AGENT_DIR and created the default HOME tree");
}

const execTool = extension.tools.get("mainframe_exec")?.definition;
if (!execTool) throw new Error("mainframe_exec definition missing");
let awmExecConfirmations = 0;
for (const [functionName, args] of [
  ["awm_project_ensure", [root]],
  ["awm_init", ["bypass", "--namespace", "projects"]],
  ["awm_checkpoint", ["bypass", "must-not-run"]],
]) {
  const denied = await execTool.execute(
    "loader-awm-exec-boundary",
    {
      functionName,
      args,
      approvalGranted: true,
      approvalNote: "loader regression only",
    },
    undefined,
    undefined,
    {
      cwd: root,
      ui: {
        confirm: async () => {
          awmExecConfirmations += 1;
          return true;
        },
      },
    },
  );
  if (denied?.details?.status !== "blocked_specialized_tool_required") {
    throw new Error(`${functionName} escaped the purpose-built mainframe_awm boundary: ${JSON.stringify(denied)}`);
  }
}
if (awmExecConfirmations !== 0) {
  throw new Error(`Reserved AWM function reached the generic confirmation UI ${awmExecConfirmations} time(s)`);
}
let lifecycleExecConfirmations = 0;
for (const [functionName, args] of [
  ["mainframe_pi_install", ["--yes"]],
  ["mainframe_pi_remove", ["--yes"]],
  ["mainframe_pi_restore", ["--backup-id", ".mainframe-pi-backup-20260812T162516Z.Ab12Cd", "--yes"]],
  ["mainframe_setup", ["--yes", "--host=pi"]],
]) {
  const denied = await execTool.execute(
    "loader-lifecycle-exec",
    {
      functionName,
      args,
      approvalGranted: true,
      approvalNote: "loader regression only",
    },
    undefined,
    undefined,
    {
      cwd: root,
      ui: {
        confirm: async () => {
          lifecycleExecConfirmations += 1;
          return true;
        },
      },
    },
  );
  if (denied?.details?.status !== "blocked_human_terminal_required") {
    throw new Error(`${functionName} escaped the human-terminal lifecycle boundary: ${JSON.stringify(denied)}`);
  }
}
if (lifecycleExecConfirmations !== 0) {
  throw new Error(`Pi lifecycle function reached the in-agent confirmation UI ${lifecycleExecConfirmations} time(s)`);
}

// The checked-in generated registry and manifest intentionally remain unchanged
// until the shell library is admitted by the normal release pipeline. Model that
// future canonical record under the extension's trusted, test-only HOME root so
// mainframe_exec's argument-sensitive lifecycle boundary is covered today.
const futureRoot = join(process.env.HOME, ".mainframe");
mkdirSync(join(futureRoot, "lib"), { recursive: true });
writeFileSync(
  join(futureRoot, "lib", "common.sh"),
  "mainframe_shell() { printf 'future-mainframe-shell:%s\\n' \"$*\"; }\n",
  { mode: 0o600 },
);
const futureRegistry = JSON.parse(readFileSync(join(root, "FUNCTIONS.json"), "utf8"));
futureRegistry.libraries.shell = {
  ...(futureRegistry.libraries.shell || {}),
  category: futureRegistry.libraries.shell?.category || "system",
  functions: {
    ...(futureRegistry.libraries.shell?.functions || {}),
    mainframe_shell: {
      description: "Inspect or repair managed shell integration.",
      signature: "mainframe_shell [status|repair]",
      params: [],
      returns: "stdout",
      idempotent: true,
      pure: false,
    },
  },
};
const futureManifest = JSON.parse(readFileSync(join(root, "MANIFEST.json"), "utf8"));
const futureCanonicalId = "mf:std:shell:mainframe_shell";
futureManifest.name_index.mainframe_shell = futureCanonicalId;
futureManifest.exports[futureCanonicalId] = {
  name: "mainframe_shell",
  owner: "shell",
  summary: "Inspect or repair managed shell integration.",
  params: [],
  result: { kind: "stdout" },
  effects: ["read", "write"],
  dependencies: [],
  platforms: ["linux", "macos"],
  stability: "stable",
  aliases: [],
  pack: "std",
  profiles: ["full"],
  ownership: "provisional",
  signature: "mainframe_shell",
  idempotent: true,
  bash_identifier: true,
};
writeFileSync(join(futureRoot, "FUNCTIONS.json"), JSON.stringify(futureRegistry), { mode: 0o600 });
writeFileSync(join(futureRoot, "MANIFEST.json"), JSON.stringify(futureManifest), { mode: 0o600 });

let futureShellConfirmations = 0;
const futureShellMutation = await execTool.execute(
  "loader-future-shell-mutation",
  {
    root: futureRoot,
    functionName: "mainframe_shell",
    args: ["repair", "--shell", "all", "--yes"],
    approvalGranted: true,
    approvalNote: "future canonical shell regression",
  },
  undefined,
  undefined,
  {
    cwd: futureRoot,
    ui: {
      confirm: async () => {
        futureShellConfirmations += 1;
        return true;
      },
    },
  },
);
if (futureShellMutation?.details?.status !== "blocked_human_terminal_required") {
  throw new Error(`canonical mainframe_shell repair escaped the external-terminal boundary: ${JSON.stringify(futureShellMutation)}`);
}
if (futureShellConfirmations !== 0) {
  throw new Error("canonical mainframe_shell repair reached Pi's in-agent confirmation UI");
}

for (const args of [
  ["status", "--shell", "all"],
  ["repair", "--shell", "all", "--dry-run"],
]) {
  let confirmationsForReadOnlyCall = 0;
  const allowed = await execTool.execute(
    "loader-future-shell-read-only",
    {
      root: futureRoot,
      functionName: "mainframe_shell",
      args,
      approvalGranted: true,
      approvalNote: "future canonical read-only shell regression",
    },
    undefined,
    undefined,
    {
      cwd: futureRoot,
      ui: {
        confirm: async () => {
          confirmationsForReadOnlyCall += 1;
          return true;
        },
      },
    },
  );
  if (allowed?.details?.status === "blocked_human_terminal_required" ||
      allowed?.details?.result?.code !== 0 ||
      !allowed?.details?.result?.stdout?.includes(`future-mainframe-shell:${args.join(" ")}`) ||
      confirmationsForReadOnlyCall !== 1) {
    throw new Error(`canonical read-only mainframe_shell call was not allowed through the standard Pi path: ${JSON.stringify({ args, allowed, confirmationsForReadOnlyCall })}`);
  }
}
let confirmations = 0;
for (const [functionName, args] of [
  ["safe_remove", ["/tmp/mainframe-pi-never-run"]],
  ["ghs_advisory_publish", ["owner/repo", "GHSA-test"]],
  ["gh_release_upload", ["owner/repo", "v0.0.0", "artifact"]],
  ["gha_secret_set", ["owner/repo", "NAME", "value"]],
  ["http_post", ["https://example.invalid", "data"]],
  ["agent_safe_exec", ["printf", "never-run"]],
]) {
  const denied = await execTool.execute(
    "loader-smoke",
    {
      functionName,
      args,
      approvalGranted: true,
      approvalNote: "loader regression only",
    },
    undefined,
    undefined,
    {
      cwd: root,
      ui: {
        confirm: async () => {
          confirmations += 1;
          return false;
        },
      },
    },
  );
  if (denied?.details?.status !== "blocked_user_declined") {
    throw new Error(`${functionName} did not fail closed: ${JSON.stringify(denied)}`);
  }
}
if (confirmations !== 6) throw new Error(`expected six human confirmations, got ${confirmations}`);

const argumentSecret = "MAINFRAME_PI_ARGUMENT_SECRET_7f93d2";
const stableArgumentUpdates = [];
const stableArgumentResult = await execTool.execute(
  "loader-stable-core-argument-redaction",
  { functionName: "array_contains", args: [argumentSecret, argumentSecret] },
  undefined,
  (update) => { stableArgumentUpdates.push(update); },
  { cwd: root, ui: {} },
);
const stableArgumentObservables = JSON.stringify({
  updates: stableArgumentUpdates,
  result: stableArgumentResult,
});
if (stableArgumentObservables.includes(argumentSecret)) {
  throw new Error(`stable-core execution leaked a raw argument outside the broker input channel: ${stableArgumentObservables}`);
}
if (stableArgumentResult?.details?.argumentMetadata?.count !== 2 ||
    JSON.stringify(stableArgumentResult?.details?.argumentMetadata?.fields) !== JSON.stringify(["needle", "items"]) ||
    !Number.isInteger(stableArgumentResult?.details?.argumentMetadata?.inputBytes) ||
    stableArgumentResult.details.argumentMetadata.inputBytes < 1) {
  throw new Error(`stable-core execution omitted safe argument metadata: ${JSON.stringify(stableArgumentResult)}`);
}

const nonstableArgumentUpdates = [];
let nonstableConfirmationPreview = "";
const nonstableArgumentResult = await execTool.execute(
  "loader-nonstable-argument-redaction",
  {
    functionName: "strlen",
    args: [argumentSecret],
    approvalGranted: true,
    approvalNote: "Pi boundary regression",
  },
  undefined,
  (update) => { nonstableArgumentUpdates.push(update); },
  {
    cwd: root,
    ui: {
      confirm: async (_title, preview) => {
        nonstableConfirmationPreview = String(preview || "");
        return true;
      },
    },
  },
);
if (!nonstableConfirmationPreview.includes(argumentSecret)) {
  throw new Error("human confirmation did not receive the separate raw-argument preview");
}
const nonstableArgumentObservables = JSON.stringify({
  updates: nonstableArgumentUpdates,
  result: nonstableArgumentResult,
});
if (nonstableArgumentObservables.includes(argumentSecret)) {
  throw new Error(`non-stable execution leaked a raw argument after confirmation: ${nonstableArgumentObservables}`);
}
if (nonstableArgumentResult?.details?.argumentMetadata?.count !== 1 ||
    !Number.isInteger(nonstableArgumentResult?.details?.argumentMetadata?.inputBytes) ||
    nonstableArgumentResult.details.argumentMetadata.inputBytes < 1) {
  throw new Error(`non-stable execution omitted safe argument metadata: ${JSON.stringify(nonstableArgumentResult)}`);
}
for (const possibleAudit of [
  auditPath,
  join(process.env.HOME, ".local", "state", "mainframe", "invocations.jsonl"),
]) {
  if (existsSync(possibleAudit) && readFileSync(possibleAudit, "utf8").includes(argumentSecret)) {
    throw new Error(`execution audit leaked a raw argument: ${possibleAudit}`);
  }
}

const stableResult = await execTool.execute(
  "loader-stable-core",
  { functionName: "json_object", args: ["tool=pi", "ok:bool=true"] },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (stableResult?.details?.risk !== "low" || stableResult?.details?.result?.code !== 0 ||
    !stableResult?.details?.result?.stdout?.includes('"ok":true')) {
  throw new Error(`stable-core execution failed: ${JSON.stringify(stableResult)}`);
}
const expectedBrokerArgs = [
  "invoke",
  "mf:data:json:json_object",
  "--input-json",
  "-",
  "--profile",
  "stable-core",
  "--format",
  "broker-json-v1",
  "--caller",
  "pi",
];
if (stableResult?.details?.result?.command !== join(root, "bin", "mainframe") ||
    stableResult?.details?.result?.argumentCount !== expectedBrokerArgs.length ||
    Object.hasOwn(stableResult?.details?.result || {}, "args") ||
    stableResult?.details?.canonicalId !== "mf:data:json:json_object" ||
    stableResult?.details?.broker?.status !== "success" ||
    !/^inv-[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$/.test(stableResult?.details?.broker?.auditId || "")) {
  throw new Error(`stable-core execution did not use the exact canonical broker contract: ${JSON.stringify(stableResult)}`);
}
const invocationAuditPath = join(process.env.HOME, ".local", "state", "mainframe", "invocations.jsonl");
const stableAudit = readFileSync(invocationAuditPath, "utf8")
  .trim()
  .split("\n")
  .map((line) => JSON.parse(line))
  .find((record) => record.audit_id === stableResult.details.broker.auditId);
if (stableAudit?.caller !== "pi" || stableAudit?.profile !== "stable-core" ||
    stableAudit?.canonical_id !== "mf:data:json:json_object" ||
    Object.hasOwn(stableAudit || {}, "args")) {
  throw new Error(`stable-core broker audit lost caller/profile identity or exposed arguments: ${JSON.stringify(stableAudit)}`);
}

const scalarResult = await execTool.execute(
  "loader-stable-core-scalars",
  { functionName: "json_get", args: ['{"name":"Ada"}', "name"] },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (scalarResult?.details?.result?.code !== 0 ||
    scalarResult?.details?.result?.stdout !== "Ada" ||
    scalarResult?.details?.broker?.canonicalId !== "mf:data:json:json_get") {
  throw new Error(`stable-core scalar mapping failed: ${JSON.stringify(scalarResult)}`);
}

const spreadResult = await execTool.execute(
  "loader-stable-core-spread",
  { functionName: "array_contains", args: ["beta", "alpha", "beta"] },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (spreadResult?.details?.result?.code !== 0 ||
    spreadResult?.details?.broker?.canonicalId !== "mf:data:pure-array:array_contains") {
  throw new Error(`stable-core scalar/spread mapping failed: ${JSON.stringify(spreadResult)}`);
}

for (const [functionName, args] of [
  ["json_get", ['{"name":"Ada"}']],
  ["validate_path", [root, "not-a-reviewed-path-type"]],
]) {
  const invalidInput = await execTool.execute(
    "loader-stable-core-invalid-input",
    { functionName, args },
    undefined,
    undefined,
    { cwd: root, ui: {} },
  );
  if (invalidInput?.details?.status !== "blocked_invalid_broker_input" || invalidInput?.details?.result) {
    throw new Error(`${functionName} escaped its closed positional broker mapping: ${JSON.stringify(invalidInput)}`);
  }
}

const isolatedRoot = join(process.env.HOME, ".mainframe");
mkdirSync(join(isolatedRoot, "lib"), { recursive: true, mode: 0o700 });
writeFileSync(join(isolatedRoot, "lib", "common.sh"), "# isolated broker-boundary fixture\n", { mode: 0o600 });
writeFileSync(join(isolatedRoot, "FUNCTIONS.json"), readFileSync(join(root, "FUNCTIONS.json")), { mode: 0o600 });
const isolatedManifestPath = join(isolatedRoot, "MANIFEST.json");
const canonicalManifest = JSON.parse(readFileSync(join(root, "MANIFEST.json"), "utf8"));
writeFileSync(isolatedManifestPath, `${JSON.stringify(canonicalManifest)}\n`, { mode: 0o600 });

const missingBroker = await execTool.execute(
  "loader-stable-core-missing-broker",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (missingBroker?.details?.status !== "blocked_broker_unavailable" || missingBroker?.details?.result) {
  throw new Error(`stable-core execution bypassed a missing canonical broker: ${JSON.stringify(missingBroker)}`);
}

const invalidManifest = structuredClone(canonicalManifest);
invalidManifest.exports["mf:data:json:json_object"].call_shape.arguments[0].mode = "shell";
writeFileSync(isolatedManifestPath, `${JSON.stringify(invalidManifest)}\n`, { mode: 0o600 });
const missingContract = await execTool.execute(
  "loader-stable-core-missing-contract",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (missingContract?.details?.status !== "blocked_broker_contract_unavailable" || missingContract?.details?.result) {
  throw new Error(`stable-core execution bypassed invalid broker metadata: ${JSON.stringify(missingContract)}`);
}

const invalidResultManifest = structuredClone(canonicalManifest);
invalidResultManifest.exports["mf:data:json:json_object"].result = { kind: "shell" };
writeFileSync(isolatedManifestPath, `${JSON.stringify(invalidResultManifest)}\n`, { mode: 0o600 });
const invalidResultContract = await execTool.execute(
  "loader-stable-core-invalid-result-contract",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (invalidResultContract?.details?.status !== "blocked_broker_contract_unavailable" || invalidResultContract?.details?.result) {
  throw new Error(`stable-core execution bypassed an invalid result contract: ${JSON.stringify(invalidResultContract)}`);
}

const extraResultMetadataManifest = structuredClone(canonicalManifest);
extraResultMetadataManifest.exports["mf:data:json:json_object"].result = { kind: "stdout", extra: true };
writeFileSync(isolatedManifestPath, `${JSON.stringify(extraResultMetadataManifest)}\n`, { mode: 0o600 });
const extraResultMetadata = await execTool.execute(
  "loader-stable-core-extra-result-metadata",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (extraResultMetadata?.details?.status !== "blocked_broker_contract_unavailable" || extraResultMetadata?.details?.result) {
  throw new Error(`Pi accepted non-exact result metadata: ${JSON.stringify(extraResultMetadata)}`);
}

writeFileSync(isolatedManifestPath, `${JSON.stringify(canonicalManifest)}\n`, { mode: 0o600 });
mkdirSync(join(isolatedRoot, "bin"), { recursive: true, mode: 0o700 });
const malformedBrokerPath = join(isolatedRoot, "bin", "mainframe");
writeFileSync(malformedBrokerPath, "#!/bin/sh\nprintf '{\"schema_version\":1}\\n'\n", { mode: 0o700 });
chmodSync(malformedBrokerPath, 0o700);
const malformedBroker = await execTool.execute(
  "loader-stable-core-malformed-envelope",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (malformedBroker?.details?.status !== "blocked_invalid_broker_response" || malformedBroker?.details?.result) {
  throw new Error(`Pi accepted a malformed broker envelope: ${JSON.stringify(malformedBroker)}`);
}

writeFileSync(
  malformedBrokerPath,
  "#!/bin/sh\n/bin/cat >/dev/null\n/bin/cat \"$MAINFRAME_ROOT/broker-envelope.json\"\n",
  { mode: 0o700 },
);
chmodSync(malformedBrokerPath, 0o700);
const brokerEnvelopePath = join(isolatedRoot, "broker-envelope.json");
const writeSuccessfulBrokerEnvelope = (functionName, stdout) => {
  const canonicalId = canonicalManifest.name_index[functionName];
  const record = canonicalManifest.exports[canonicalId];
  const envelope = {
    audit_id: "inv-20260809T000000Z-1-1",
    canonical_id: canonicalId,
    duration_ms: 1,
    error: null,
    exit_code: 0,
    name: functionName,
    ok: true,
    output_exceeded: false,
    owner: record.owner,
    schema_version: 1,
    status: "success",
    stderr_b64: "",
    stdout_b64: Buffer.from(stdout, "utf8").toString("base64"),
    timed_out: false,
  };
  writeFileSync(brokerEnvelopePath, `${JSON.stringify(envelope)}\n`, { mode: 0o600 });
};

writeFileSync(isolatedManifestPath, `${JSON.stringify(canonicalManifest)}\n`, { mode: 0o600 });
writeSuccessfulBrokerEnvelope("array_contains", "forged-exit-output");
const forgedExitStdout = await execTool.execute(
  "loader-stable-core-exit-kind-stdout",
  { functionName: "array_contains", args: ["x", "x"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (forgedExitStdout?.details?.status !== "blocked_invalid_broker_response" || forgedExitStdout?.details?.result) {
  throw new Error(`Pi accepted stdout that contradicted an exit-kind result: ${JSON.stringify(forgedExitStdout)}`);
}

const noneResultManifest = structuredClone(canonicalManifest);
noneResultManifest.exports["mf:data:json:json_object"].result = { kind: "none" };
writeFileSync(isolatedManifestPath, `${JSON.stringify(noneResultManifest)}\n`, { mode: 0o600 });
writeSuccessfulBrokerEnvelope("json_object", "forged-none-output");
const forgedNoneStdout = await execTool.execute(
  "loader-stable-core-none-kind-stdout",
  { functionName: "json_object", args: ["tool=pi"], root: isolatedRoot },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (forgedNoneStdout?.details?.status !== "blocked_invalid_broker_response" || forgedNoneStdout?.details?.result) {
  throw new Error(`Pi accepted stdout that contradicted a none-kind result: ${JSON.stringify(forgedNoneStdout)}`);
}

writeFileSync(isolatedManifestPath, `${JSON.stringify(canonicalManifest)}\n`, { mode: 0o600 });
for (const exactStdout of ["", " \n\t"]) {
  writeSuccessfulBrokerEnvelope("json_object", exactStdout);
  const exactStdoutResult = await execTool.execute(
    "loader-stable-core-exact-stdout",
    { functionName: "json_object", args: [], root: isolatedRoot },
    undefined,
    undefined,
    { cwd: root, ui: {} },
  );
  if (exactStdoutResult?.details?.result?.stdout !== exactStdout) {
    throw new Error(`Pi changed exact stdout bytes: ${JSON.stringify({ expected: exactStdout, result: exactStdoutResult })}`);
  }
  const contentText = exactStdoutResult?.content?.map((item) => item?.text || "").join("") || "";
  let transport;
  try {
    transport = JSON.parse(contentText);
  } catch {
    throw new Error(`Pi did not preserve empty or whitespace stdout in a lossless text transport: ${JSON.stringify(exactStdoutResult)}`);
  }
  if (transport?.schema_version !== 1 || transport?.kind !== "mainframe-pi-stdout" ||
      transport?.function !== "json_object" || transport?.encoding !== "base64" ||
      Buffer.from(String(transport?.stdout_b64 || ""), "base64").toString("utf8") !== exactStdout) {
    throw new Error(`Pi stdout transport was not exact: ${JSON.stringify({ exactStdout, transport })}`);
  }
}

const awmTool = extension.tools.get("mainframe_awm")?.definition;
if (!awmTool) throw new Error("mainframe_awm definition missing");
const awmInit = await awmTool.execute(
  "loader-awm-init",
  { action: "init", name: "pi-impact-handoff", namespace: "pi-impact-test" },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
const awmSession = awmInit?.details?.result?.stdout || "";
if (awmInit?.details?.result?.code !== 0 || !/^[a-f0-9]{12}$/.test(awmSession)) {
  throw new Error(`AWM init failed: ${JSON.stringify(awmInit)}`);
}
const awmCheckpoint = await awmTool.execute(
  "loader-awm-checkpoint",
  {
    action: "checkpoint",
    session: awmSession,
    key: "implementation-root-cause",
    value: "subtract used capacity from total capacity",
    importance: "critical",
  },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
if (awmCheckpoint?.details?.result?.code !== 0) {
  throw new Error(`AWM checkpoint failed: ${JSON.stringify(awmCheckpoint)}`);
}
const awmContext = await awmTool.execute(
  "loader-awm-context",
  { action: "context_for", session: awmSession, query: "implementation", tokens: 512 },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
const awmContextText = awmContext?.details?.result?.stdout || "";
const awmContextJson = JSON.parse(awmContextText);
if (awmContext?.details?.result?.code !== 0 ||
    awmContextJson.max_tokens !== 512 ||
    awmContextJson?.budget?.requested_tokens !== 512 ||
    awmContextJson?.budget?.max_chars !== 2048 ||
    awmContextJson?.budget?.actual_chars > 2048 ||
    !awmContextText.includes("subtract used capacity from total capacity")) {
  throw new Error(`AWM context did not honor the Pi budget: ${JSON.stringify(awmContext)}`);
}
const awmHandoff = await awmTool.execute(
  "loader-awm-handoff",
  { action: "handoff_prepare", session: awmSession, message: "implementer", tokens: 1024 },
  undefined,
  undefined,
  { cwd: root, ui: {} },
);
const awmHandoffText = awmHandoff?.details?.result?.stdout || "";
const awmHandoffJson = JSON.parse(awmHandoffText);
if (awmHandoff?.details?.result?.code !== 0 ||
    awmHandoffJson.type !== "handoff" ||
    awmHandoffJson.parent_session !== awmSession ||
    awmHandoffJson.target_agent !== "implementer" ||
    awmHandoffJson?.budget?.requested_tokens !== 1024 ||
    awmHandoffJson?.budget?.max_chars !== 4096 ||
    awmHandoffJson?.budget?.actual_chars > 4096 ||
    awmHandoffJson?.context?.max_tokens !== 1024 ||
    Buffer.byteLength(awmHandoffText) > 4096) {
  throw new Error(`AWM handoff did not honor the Pi budget: ${JSON.stringify(awmHandoff)}`);
}
const exportDenied = await awmTool.execute(
  "loader-awm-export",
  { action: "export", value: join(process.env.HOME, "mainframe-pi-export-never-created.json") },
  undefined,
  undefined,
  { cwd: root, ui: { confirm: async () => false } },
);
if (exportDenied?.details?.status !== "blocked_user_declined") {
  throw new Error(`AWM export did not fail closed: ${JSON.stringify(exportDenied)}`);
}
console.log("Pi loader, prompt, bounded AWM handoff, agent/TUI bash, gate, canonical export, and human confirmation contracts pass");
JS

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi loader, prompt, bounded AWM handoff, agent/TUI bash, gate, canonical export, and human confirmation contracts pass" ]]
}

@test "Pi readiness derives from effective tools and fails closed on runtime or core doctor failure" {
    local pi_bin node_bin fixture_root fixture_home fixture_agent
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"
    fixture_root="$TEST_ROOT/badge-package"
    fixture_home="$TEST_ROOT/badge-home"
    fixture_agent="$TEST_ROOT/badge-agent"
    mkdir -p \
        "$fixture_root/skills/pi/extensions" \
        "$fixture_root/security" \
        "$fixture_root/config" \
        "$fixture_root/lib" \
        "$fixture_root/bin" \
        "$fixture_home" \
        "$fixture_agent"
    cp "$PROJECT_ROOT/skills/pi/extensions/mainframe.ts" "$fixture_root/skills/pi/extensions/mainframe.ts"
    cp "$PROJECT_ROOT/security/gate-rules.json" "$fixture_root/security/gate-rules.json"
    cp "$PROJECT_ROOT/security/gate-normalizer.mjs" "$fixture_root/security/gate-normalizer.mjs"
    cp "$PROJECT_ROOT/config/pi-compatibility.json" "$fixture_root/config/pi-compatibility.json"
    cp "$PROJECT_ROOT/VERSION" "$fixture_root/VERSION"
    printf '%s\n' '# badge fixture runtime marker' > "$fixture_root/lib/common.sh"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "${1:-} ${2:-} ${3:-}" = "pi status --json" ]; then' \
        "  printf '%s\\n' '{\"state\":\"ready\",\"package_active\":true,\"package_source\":\"$fixture_root\",\"mainframe_root\":\"$fixture_root\"}'" \
        '  exit 0' \
        'fi' \
        'if [ "${1:-}" = "doctor" ]; then' \
        '  exit 42' \
        'fi' \
        'exit 64' > "$fixture_root/bin/mainframe"
    chmod 700 "$fixture_root/bin/mainframe"

    run env \
        HOME="$fixture_home" \
        PI_CODING_AGENT_DIR="$fixture_agent" \
        "$node_bin" --input-type=module - "$fixture_root" "$pi_bin" <<'JS'
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const root = realpathSync(process.argv[2]);
const piBin = realpathSync(process.argv[3]);
const loaderPath = join(dirname(piBin), "core", "extensions", "loader.js");
const certifiedPiRoot = join(root, "certified-pi-runtime");
const certifiedPiCli = join(certifiedPiRoot, "dist", "cli.js");
mkdirSync(dirname(certifiedPiCli), { recursive: true });
writeFileSync(certifiedPiCli, "// exact certified Pi identity fixture\n");
writeFileSync(join(certifiedPiRoot, "package.json"), JSON.stringify({
  name: "@earendil-works/pi-coding-agent",
  version: "0.84.2",
  bin: { pi: "dist/cli.js" },
}));
const os = process.platform === "darwin" ? "Darwin" : process.platform === "linux" ? "Linux" : process.platform;
const arch = process.arch === "x64" ? "x86_64" : process.arch === "arm64" ? "arm64" : process.arch;
let libc = os === "Darwin" ? "none" : "unknown";
if (os === "Linux" && process.report?.getReport?.()?.header?.glibcVersionRuntime) libc = "glibc";
const currentPlatform = `${os}-${arch}-${libc}`;
const compatibilityPath = join(root, "config", "pi-compatibility.json");
const compatibility = JSON.parse(readFileSync(compatibilityPath, "utf8"));
const certified = compatibility.certifications.find((record) =>
  record.package === "@earendil-works/pi-coding-agent" && record.version === "0.84.2");
if (!certified || !Array.isArray(certified.platforms)) {
  throw new Error("badge fixture could not locate the exact certified Pi record");
}
if (!certified.platforms.includes(currentPlatform)) certified.platforms.push(currentPlatform);
writeFileSync(compatibilityPath, `${JSON.stringify(compatibility, null, 2)}\n`);
const { createExtensionRuntime, loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(root, "skills", "pi", "extensions", "mainframe.ts");
process.argv[1] = realpathSync(certifiedPiCli);
const injectedRuntime = createExtensionRuntime();
let allTools = [];
let activeTools = [];
const loaded = await loadExtensions([extensionPath], root, undefined, injectedRuntime);
const { extensions, errors } = loaded;
if (errors.length || extensions.length !== 1) {
  throw new Error(`badge fixture extension failed to load: ${JSON.stringify(errors)}`);
}
// Pi 0.73.x creates its own runtime inside loadExtensions and returns it, while
// newer Pi accepts an injected runtime. Drive the runtime that the loaded API
// actually closes over so this product-readiness test remains deterministic.
const runtime = loaded.runtime;
if (!runtime || typeof runtime !== "object") {
  throw new Error("badge fixture loader did not expose its effective extension runtime");
}
runtime.getAllTools = () => allTools;
runtime.getActiveTools = () => activeTools;
const extension = extensions[0];
if (extension.tools.size !== 7 || (extension.handlers.get("before_agent_start") || []).length !== 1 ||
    (extension.handlers.get("tool_call") || []).length !== 1 ||
    (extension.handlers.get("user_bash") || []).length !== 1) {
  throw new Error("readiness badge changed the certified seven-tool/three-hook surface");
}
const toolNames = [...extension.tools.keys()].sort();
const canonicalSourceInfo = {
  path: extensionPath,
  source: root,
  scope: "user",
  origin: "package",
  baseDir: root,
};
allTools = toolNames.map((name) => ({ name, sourceInfo: { ...canonicalSourceInfo } }));
activeTools = [...toolNames];
const command = extension.commands.get("mainframe");
if (!command?.handler) throw new Error("/mainframe command is missing");
const statuses = [];
const notices = [];
const context = {
  cwd: root,
  ui: {
    setStatus: (key, text) => statuses.push({ key, text }),
    notify: (message, level) => notices.push({ message, level }),
  },
};
await command.handler("status", context);
const statusBadge = statuses.at(-1);
if (statusBadge?.key !== "mainframe" || statusBadge?.text !== "MF READY" ||
    !notices.at(-1)?.message?.includes("tools=7/7 effective (present=7, active=7, canonical=7; proof=verified)")) {
  throw new Error(`/mainframe status did not prove the effective tool surface: ${JSON.stringify({ statuses, notices })}`);
}

activeTools = toolNames.filter((name) => name !== "mainframe_exec");
await command.handler("status", context);
const inactiveBadge = statuses.at(-1);
if (inactiveBadge?.key !== "mainframe" || inactiveBadge?.text !== "MF BLOCKED" ||
    !notices.at(-1)?.message?.includes("tools=6/7 effective (present=7, active=6, canonical=7; proof=inactive)") ||
    !notices.at(-1)?.message?.includes("mainframe_exec")) {
  throw new Error(`an inactive required tool did not fail readiness closed: ${JSON.stringify({ statuses, notices })}`);
}

activeTools = [...toolNames];
allTools = allTools.filter((tool) => tool.name !== "mainframe_exec");
await command.handler("status", context);
const missingBadge = statuses.at(-1);
if (missingBadge?.key !== "mainframe" || missingBadge?.text !== "MF BLOCKED" ||
    !notices.at(-1)?.message?.includes("tools=6/7 effective (present=6, active=6, canonical=6; proof=missing)") ||
    !notices.at(-1)?.message?.includes("mainframe_exec")) {
  throw new Error(`a missing required tool did not fail readiness closed: ${JSON.stringify({ statuses, notices })}`);
}

allTools = toolNames.map((name) => ({ name, sourceInfo: { ...canonicalSourceInfo } }));
allTools = allTools.map((tool) => tool.name === "mainframe_exec"
  ? { ...tool, sourceInfo: { ...tool.sourceInfo, path: join(root, "foreign", "mainframe.ts") } }
  : tool);
await command.handler("status", context);
const sourceBadge = statuses.at(-1);
if (sourceBadge?.key !== "mainframe" || sourceBadge?.text !== "MF RELOAD_REQUIRED" ||
    !notices.at(-1)?.message?.includes("tools=6/7 effective (present=7, active=7, canonical=6; proof=source-mismatch)") ||
    !notices.at(-1)?.message?.includes("mainframe_exec")) {
  throw new Error(`a foreign required tool did not invalidate canonical readiness: ${JSON.stringify({ statuses, notices })}`);
}

allTools = toolNames.map((name) => ({ name, sourceInfo: { ...canonicalSourceInfo } }));
runtime.getAllTools = () => { throw new Error("legacy tool API unavailable"); };
await command.handler("status", context);
const unavailableBadge = statuses.at(-1);
if (unavailableBadge?.key !== "mainframe" || unavailableBadge?.text !== "MF BLOCKED" ||
    !notices.at(-1)?.message?.includes("tools=0/7 effective") ||
    !notices.at(-1)?.message?.includes("proof=api-unavailable")) {
  throw new Error(`an unavailable certified tool API did not fail readiness closed: ${JSON.stringify({ statuses, notices })}`);
}

const legacyPiRoot = join(root, "legacy-pi-runtime");
const legacyPiCli = join(legacyPiRoot, "dist", "cli.js");
mkdirSync(join(legacyPiRoot, "dist"), { recursive: true });
writeFileSync(legacyPiCli, "// compatibility-limited Pi fixture\n");
writeFileSync(join(legacyPiRoot, "package.json"), JSON.stringify({
  name: "@mariozechner/pi-coding-agent",
  version: "0.73.1",
  bin: { pi: "dist/cli.js" },
}));
process.argv[1] = legacyPiCli;
await command.handler("status", context);
const legacyBadge = statuses.at(-1);
const legacyCertifiedPlatform = process.platform === "darwin" && process.arch === "arm64";
if (legacyBadge?.key !== "mainframe" ||
    legacyBadge?.text !== (legacyCertifiedPlatform ? "MF LIMITED" : "MF UNVERIFIED") ||
    !notices.at(-1)?.message?.includes("tools=0/7 effective") ||
    !notices.at(-1)?.message?.includes("proof=api-unavailable") ||
    (legacyCertifiedPlatform && !notices.at(-1)?.message?.includes("compatibility-limited"))) {
  throw new Error(`a legacy Pi tool API did not retain honest compatibility semantics: ${JSON.stringify({ statuses, notices })}`);
}

process.argv[1] = realpathSync(certifiedPiCli);
runtime.getAllTools = () => allTools;
await command.handler("doctor", context);
const doctorBadge = statuses.at(-1);
if (doctorBadge?.key !== "mainframe" || doctorBadge?.text !== "MF BLOCKED") {
  throw new Error(`core doctor failure did not fail the badge closed: ${JSON.stringify({ statuses, notices })}`);
}
if (!notices.some(({ message, level }) =>
  level === "error" &&
  message.includes("The core MAINFRAME shell doctor failed with exit 42.") &&
  message.includes("Core shell doctor: exit=42 (failed)"))) {
  throw new Error(`core doctor failure was not reported honestly: ${JSON.stringify(notices)}`);
}
for (const path of [
  join(process.env.HOME, ".mainframe-pi"),
  join(process.env.PI_CODING_AGENT_DIR, ".mainframe-pi"),
]) {
  if (existsSync(path)) throw new Error(`readiness badge wrote unexpected state: ${path}`);
}
console.log("Pi effective-tool readiness and doctor-failure contracts pass");
JS

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi effective-tool readiness and doctor-failure contracts pass" ]]
}

@test "Pi registry search is canonical, safety-aware, example-backed, and consistent with help" {
    local pi_bin node_bin loader_home loader_agent
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"
    loader_home="$TEST_ROOT/search-home"
    loader_agent="$TEST_ROOT/search-agent"
    mkdir -p "$loader_home" "$loader_agent"

    run env \
        HOME="$loader_home" \
        PI_CODING_AGENT_DIR="$loader_agent" \
        "$node_bin" --input-type=module - "$PROJECT_ROOT" "$pi_bin" <<'JS'
import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const root = realpathSync(process.argv[2]);
const piCli = realpathSync(process.argv[3]);
const loaderPath = join(dirname(piCli), "core", "extensions", "loader.js");
if (!existsSync(loaderPath)) throw new Error(`Pi extension loader not found: ${loaderPath}`);
const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(root, "skills", "pi", "extensions", "mainframe.ts");
const { extensions, errors } = await loadExtensions([extensionPath], root);
if (errors.length) throw new Error(JSON.stringify(errors));
const extension = extensions[0];
const searchTool = extension.tools.get("mainframe_search")?.definition;
const helpTool = extension.tools.get("mainframe_help")?.definition;
if (!searchTool || !helpTool) throw new Error("Pi search/help tools are missing");
const ctx = { cwd: root, ui: {} };

async function search(query, purpose = undefined, limit = 20) {
  const params = purpose ? { query, purpose, limit } : { query, limit };
  return searchTool.execute(`search-${query}`, params, undefined, undefined, ctx);
}

const invalid = await search("ci detect");
if (invalid?.details?.purpose !== "script" ||
    invalid?.details?.matches?.some((record) => record.function === "ci::detect" ||
      !/^[A-Za-z_][A-Za-z0-9_]*$/.test(record.function))) {
  throw new Error(`search returned a Bash name rejected by help/exec: ${JSON.stringify(invalid)}`);
}

const agent = await search("agent register");
const agentMatches = agent?.details?.matches?.filter((record) => record.function === "agent_register") || [];
if (agentMatches.length !== 1 || agentMatches[0].owner !== "agent_comm" ||
    agentMatches[0].library !== "agent_comm" ||
    agentMatches[0].canonicalId !== "mf:std:agent_comm:agent_register") {
  throw new Error(`search did not resolve the canonical agent owner: ${JSON.stringify(agentMatches)}`);
}
const agentHelp = await helpTool.execute(
  "help-agent-register",
  { functionName: "agent_register" },
  undefined,
  undefined,
  ctx,
);
if (agentHelp?.details?.library !== agentMatches[0].owner ||
    agentHelp?.details?.canonicalId !== agentMatches[0].canonicalId ||
    agentHelp?.details?.status) {
  throw new Error(`search and help disagree on the canonical export: ${JSON.stringify({ agentMatches, agentHelp })}`);
}

const directory = await search("create directory");
const directoryNames = directory?.details?.matches?.map((record) => record.function) || [];
const ensureIndex = directoryNames.indexOf("ensure_dir");
const createIndex = directoryNames.indexOf("dir_create");
if (ensureIndex < 0 || createIndex < 0 || ensureIndex >= createIndex ||
    directory.details.matches[ensureIndex].idempotent !== true ||
    directory.details.matches[ensureIndex].score !== directory.details.matches[createIndex].score) {
  throw new Error(`safety/idempotence did not break an equal-relevance tie: ${JSON.stringify(directory)}`);
}

const exampleSearch = await search("localhost:3000");
const parseUrl = exampleSearch?.details?.matches?.find((record) => record.function === "parse_url");
if (!parseUrl || !parseUrl.examples.includes('parse_url "http://localhost:3000/api/v1"')) {
  throw new Error(`registry example was not searchable and bounded: ${JSON.stringify(exampleSearch)}`);
}
const parseUrlHelp = await helpTool.execute(
  "help-parse-url",
  { functionName: "parse_url" },
  undefined,
  undefined,
  ctx,
);
const parseUrlHelpText = parseUrlHelp?.content?.map((item) => item?.text || "").join("\n") || "";
if (!parseUrlHelpText.includes("Examples:") || !parseUrlHelpText.includes('parse_url "http://localhost:3000/api/v1"')) {
  throw new Error(`help did not expose the bounded example: ${parseUrlHelpText}`);
}

const brokered = await search("json object", "execute");
const jsonObject = brokered?.details?.matches?.find((record) => record.function === "json_object");
if (!jsonObject || jsonObject.owner !== "json" || jsonObject.risk !== "low" ||
    jsonObject.stableCore !== true || jsonObject.brokerReady !== true ||
    jsonObject.specialized !== false || jsonObject.approvalRequired !== false ||
    jsonObject.approvalStatus !== "not-required" ||
    jsonObject.executionDisposition !== "brokered" || jsonObject.execEligible !== true) {
  throw new Error(`stable-core execution metadata is incomplete: ${JSON.stringify(jsonObject)}`);
}
const scriptAwm = await search("awm init", "script");
const executeAwm = await search("awm init", "execute");
if (!scriptAwm.details.matches.some((record) => record.function === "awm_init" &&
      record.specialized === true && record.executionDisposition === "specialized-tool-required") ||
    executeAwm.details.matches.some((record) => record.specialized || !record.execEligible)) {
  throw new Error(`purpose filtering did not route specialized functions: ${JSON.stringify({ scriptAwm, executeAwm })}`);
}

for (const result of [agent, directory, exampleSearch, brokered, scriptAwm]) {
  for (const record of result.details.matches) {
    const help = await helpTool.execute(
      `help-${record.function}`,
      { functionName: record.function },
      undefined,
      undefined,
      ctx,
    );
    if (help?.details?.status || help?.details?.canonicalId !== record.canonicalId ||
        help?.details?.library !== record.owner) {
      throw new Error(`search result is not help-consistent: ${JSON.stringify({ record, help })}`);
    }
  }
}

console.log("Pi canonical search, safety ranking, examples, purpose routing, and help parity pass");
JS

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi canonical search, safety ranking, examples, purpose routing, and help parity pass" ]]
}

@test "Pi RPC works hand-in-glove with Mainframe from zsh and bash caller environments" {
    local pi_bin node_bin
    if [[ "${MAINFRAME_PI_RPC_USER_BASH:-1}" != 1 ]]; then
        skip "this Pi version does not emit user_bash for the RPC bash command"
    fi
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"

    run python3 - "$PROJECT_ROOT" "$pi_bin" "$node_bin" "$TEST_ROOT" <<'PY'
import json
import os
import pathlib
import queue
import shlex
import subprocess
import sys
import threading
import time

root = pathlib.Path(sys.argv[1]).resolve()
pi_bin = pathlib.Path(sys.argv[2]).resolve()
node_bin = pathlib.Path(sys.argv[3]).resolve()
test_root = pathlib.Path(sys.argv[4]).resolve()
extension = root / "skills" / "pi" / "extensions" / "mainframe.ts"
skill = root / "skills" / "pi"


def start_reader(process):
    events = queue.Queue()

    def pump():
        try:
            for line in process.stdout:
                events.put(("event", json.loads(line)))
        except BaseException as error:
            events.put(("error", repr(error)))
        finally:
            events.put(("eof", None))

    reader = threading.Thread(target=pump, name="pi-rpc-stdout", daemon=True)
    reader.start()
    return events, reader


def receive(process, events, predicate, timeout=15):
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        try:
            kind, payload = events.get(timeout=remaining)
        except queue.Empty:
            break
        if kind == "error":
            raise AssertionError(f"Pi RPC reader failed: {payload}; seen={seen}")
        if kind == "eof":
            stderr = process.stderr.read()
            raise AssertionError(f"Pi exited early rc={process.poll()}: {stderr}; seen={seen}")
        seen.append(payload)
        if predicate(payload):
            return payload, seen
    raise AssertionError(f"timed out waiting for Pi RPC response; seen={seen}")


def send(process, payload):
    process.stdin.write(json.dumps(payload) + "\n")
    process.stdin.flush()


def run_shell_case(shell):
    case = test_root / shell.rsplit("/", 1)[-1]
    home = case / "home"
    agent_dir = case / "agent"
    home.mkdir(parents=True)
    agent_dir.mkdir(parents=True)
    poison_marker = case / "bash-env-executed"
    poison_env = case / "bash-env-poison.sh"
    poison_env.write_text(
        f"printf poison > {shlex.quote(str(poison_marker))}\n",
        encoding="utf-8",
    )
    env = {
        "BASH_ENV": str(poison_env),
        "ENV": str(poison_env),
        "HOME": str(home),
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "PI_CODING_AGENT_DIR": str(agent_dir),
        "PI_OFFLINE": "1",
        "SHELL": shell,
        "TMPDIR": str(case),
    }
    process = subprocess.Popen(
        [
            str(node_bin),
            str(pi_bin),
            "--offline",
            "--no-session",
            "--mode", "rpc",
            "--no-extensions",
            "--no-skills",
            "--no-context-files",
            "--extension", str(extension),
            "--skill", str(skill),
        ],
        cwd=root,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    events, reader = start_reader(process)
    try:
        send(process, {"type": "get_commands"})
        response, _ = receive(process, events, lambda e: e.get("type") == "response" and e.get("command") == "get_commands")
        commands = response["data"]["commands"]
        assert any(c.get("name") == "mainframe" and c.get("source") == "extension" for c in commands), commands
        assert any(c.get("name") == "skill:mainframe" and c.get("source") == "skill" for c in commands), commands

        send(process, {"type": "prompt", "message": "/mainframe status"})
        _, status_events = receive(process, events, lambda e: e.get("type") == "response" and e.get("command") == "prompt")
        notices = [e.get("message", "") for e in status_events if e.get("method") == "notify"]
        assert any("MAINFRAME + Pi: SETUP_REQUIRED" in message and "gate=10.2.0:43" in message and "tools=0/7 effective" in message and "proof=provenance-unavailable" in message for message in notices), notices

        send(process, {"type": "prompt", "message": "/mainframe doctor"})
        _, doctor_events = receive(
            process,
            events,
            lambda e: e.get("type") == "response" and e.get("command") == "prompt",
            timeout=30,
        )
        doctor_notices = [e.get("message", "") for e in doctor_events if e.get("method") == "notify"]
        assert any(
            "MAINFRAME + Pi: SETUP_REQUIRED" in message
            and "Runtime:     extension loaded; command 1/1; tools 0/7 effective (present=7, active=7, canonical=0, proof=provenance-unavailable); hooks 3/3" in message
            and "Core shell doctor: exit=0 (passed)" in message
            for message in doctor_notices
        ), doctor_notices

        send(process, {"id": "runtime", "type": "bash", "command": "declare -F json_object >/dev/null && type -P mainframe >/dev/null && printf pi-mainframe-runtime-ok"})
        runtime, _ = receive(process, events, lambda e: e.get("id") == "runtime" and e.get("type") == "response")
        assert runtime["data"]["exitCode"] == 0, runtime
        assert runtime["data"]["output"] == "pi-mainframe-runtime-ok", runtime
        assert not poison_marker.exists(), "Pi's initial Bash executed inherited BASH_ENV before the protected wrapper"

        literal_text = "rm -rf /tmp/mainframe-pi-literal-only"
        send(process, {"id": "literal", "type": "bash", "command": f"printf '%s' '{literal_text}'"})
        literal, _ = receive(process, events, lambda e: e.get("id") == "literal" and e.get("type") == "response")
        assert literal["data"]["exitCode"] == 0, literal
        assert literal["data"]["output"] == literal_text, literal

        send(process, {"id": "blocked", "type": "bash", "command": "op=rm; $op -r -f /tmp/mainframe-pi-never-run"})
        blocked, _ = receive(process, events, lambda e: e.get("id") == "blocked" and e.get("type") == "response")
        assert blocked["data"]["exitCode"] == 126, blocked
        assert "dynamic-executable-word" in blocked["data"]["output"], blocked

        lifecycle_commands = {
            "pi-install": ("mainframe pi install --yes", "pi-lifecycle-human-confirmation-required"),
            "pi-remove": ("mainframe pi remove --yes", "pi-lifecycle-human-confirmation-required"),
            "pi-restore": ("mainframe pi restore --backup-id .mainframe-pi-backup-20260812T162516Z.Ab12Cd --yes", "pi-lifecycle-human-confirmation-required"),
            "pi-setup": ("mainframe setup --yes --host pi", "pi-lifecycle-human-confirmation-required"),
            "shell-repair": ("mainframe shell repair --shell all --yes", "mainframe-shell-lifecycle-human-terminal-required"),
        }
        for request_id, (command, reason) in lifecycle_commands.items():
            send(process, {"id": request_id, "type": "bash", "command": command})
            lifecycle, _ = receive(
                process,
                events,
                lambda e, expected=request_id: e.get("id") == expected and e.get("type") == "response",
            )
            assert lifecycle["data"]["exitCode"] == 126, lifecycle
            assert reason in lifecycle["data"]["output"], lifecycle

        read_only_shell_commands = {
            "shell-status": "mainframe shell status --shell all",
            "shell-repair-dry-run": "mainframe shell repair --shell all --dry-run",
        }
        for request_id, command in read_only_shell_commands.items():
            send(process, {"id": request_id, "type": "bash", "command": command})
            read_only, _ = receive(
                process,
                events,
                lambda e, expected=request_id: e.get("id") == expected and e.get("type") == "response",
            )
            assert not (
                read_only["data"]["exitCode"] == 126
                or "mainframe-shell-lifecycle-human-terminal-required" in read_only["data"]["output"]
            ), read_only
        for profile in (".bashrc", ".bash_profile", ".bash_login", ".profile", ".zshrc"):
            assert not (home / profile).exists(), f"read-only RPC shell lifecycle created {profile}"

        runtime_mutations = {
            "mainframe-update": ("mainframe update", "mainframe-runtime-mutation-human-terminal-required"),
            "mainframe-upgrade": ("mainframe upgrade --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"),
            "mainframe-upgrade-obfuscated": ("m=mainframe; $m up'grade' --confirm-agents-stopped", "mainframe-runtime-mutation-human-terminal-required"),
            "brew-upgrade": ("brew upgrade mainframe", "homebrew-mainframe-mutation-human-terminal-required"),
            "brew-uninstall-obfuscated": ("b=brew; $b un'install' gtwatts/mainframe/mainframe", "homebrew-mainframe-mutation-human-terminal-required"),
        }
        for request_id, (command, reason) in runtime_mutations.items():
            send(process, {"id": request_id, "type": "bash", "command": command})
            mutation, _ = receive(
                process,
                events,
                lambda e, expected=request_id: e.get("id") == expected and e.get("type") == "response",
            )
            assert mutation["data"]["exitCode"] == 126, mutation
            assert reason in mutation["data"]["output"], mutation
            assert not poison_marker.exists(), f"blocked runtime mutation inherited BASH_ENV: {request_id}"

        send(process, {"type": "prompt", "message": "/mainframe classify mainframe upgrade --confirm-agents-stopped"})
        _, classify_events = receive(
            process,
            events,
            lambda e: e.get("type") == "response" and e.get("command") == "prompt",
        )
        classify_notices = [e.get("message", "") for e in classify_events if e.get("method") == "notify"]
        assert any(
            "blocked" in message and "mainframe-runtime-mutation-human-terminal-required" in message
            for message in classify_notices
        ), classify_notices

        send(process, {"type": "prompt", "message": "/mainframe classify mainframe upgrade --dry-run"})
        _, dry_run_events = receive(
            process,
            events,
            lambda e: e.get("type") == "response" and e.get("command") == "prompt",
        )
        dry_run_notices = [e.get("message", "") for e in dry_run_events if e.get("method") == "notify"]
        assert any("allowed" in message for message in dry_run_notices), dry_run_notices
        assert not (agent_dir / "settings.json").exists(), "blocked Pi lifecycle mutated settings"
        assert not (agent_dir / ".mainframe-pi-receipt.json").exists(), "blocked Pi lifecycle wrote a receipt"
    finally:
        if process.stdin:
            process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        reader.join(timeout=2)
        assert not reader.is_alive(), "Pi RPC stdout reader did not stop"
        if process.stderr:
            stderr = process.stderr.read()
            assert process.returncode == 0, f"Pi shutdown rc={process.returncode}: {stderr}"


for caller_shell in ("/bin/zsh", "/bin/bash"):
    run_shell_case(caller_shell)
print("Pi RPC passed from zsh and bash caller environments")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi RPC passed from zsh and bash caller environments" ]]
}

@test "Pi discovers Mainframe through its real local-package install path" {
    local pi_bin node_bin package_home package_agent
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"
    package_home="$TEST_ROOT/package-home"
    package_agent="$TEST_ROOT/package-agent"
    mkdir -p "$package_home" "$package_agent"

    run env \
        HOME="$package_home" \
        PI_CODING_AGENT_DIR="$package_agent" \
        PI_OFFLINE=1 \
        "$pi_bin" install "$PROJECT_ROOT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Installed $PROJECT_ROOT"* ]]

    # Pi's native installer records a relative package path. The human-facing
    # MAINFRAME lifecycle canonicalizes that exact active package and adds its
    # private upgrade/removal receipt before live readiness can be claimed.
    run env \
        HOME="$package_home" \
        PI_CODING_AGENT_DIR="$package_agent" \
        "$PROJECT_ROOT/bin/mainframe" pi install --yes
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'changed=true'* ]]

    run python3 - "$PROJECT_ROOT" "$pi_bin" "$node_bin" "$TEST_ROOT" "$package_home" "$package_agent" "${MAINFRAME_PI_RPC_USER_BASH:-1}" <<'PY'
import json
import hashlib
import os
import pathlib
import platform
import queue
import shlex
import stat
import subprocess
import sys
import threading
import time

root = pathlib.Path(sys.argv[1]).resolve()
pi_bin = pathlib.Path(sys.argv[2]).resolve()
node_bin = pathlib.Path(sys.argv[3]).resolve()
test_root = pathlib.Path(sys.argv[4]).resolve()
home = pathlib.Path(sys.argv[5]).resolve()
agent_dir = pathlib.Path(sys.argv[6]).resolve()
rpc_user_bash = sys.argv[7] == "1"
settings_path = agent_dir / "settings.json"
settings_before = settings_path.read_text(encoding="utf-8")
receipt_path = agent_dir / ".mainframe-pi-receipt.json"
receipt_before = receipt_path.read_text(encoding="utf-8")
settings = json.loads(settings_before)
packages = settings.get("packages", [])
assert len(packages) == 1 and isinstance(packages[0], str), settings
sentinel_dir = test_root / "installed-package-deny-sentinel"
sentinel_dir.mkdir(mode=0o700)
sentinel_path = sentinel_dir / "must-survive.bin"
sentinel_content = os.urandom(257)
sentinel_path.write_bytes(sentinel_content)
sentinel_path.chmod(0o600)
sentinel_digest = hashlib.sha256(sentinel_content).hexdigest()

pi_manifest = json.loads((pi_bin.resolve().parent.parent / "package.json").read_text(encoding="utf-8"))
system = platform.system()
machine = platform.machine()
if machine == "AMD64":
    machine = "x86_64"
elif machine == "aarch64":
    machine = "arm64"
libc = "none" if system == "Darwin" else "glibc" if platform.libc_ver()[0] == "glibc" else "unknown"
platform_tuple = f"{system}-{machine}-{libc}"
compatibility = json.loads((root / "config" / "pi-compatibility.json").read_text(encoding="utf-8"))
matches = [
    record for record in compatibility["certifications"]
    if record["mainframe_version"] == compatibility["mainframe_version"]
    and record["package"] == pi_manifest["name"]
    and record["version"] == pi_manifest["version"]
    and platform_tuple in record["platforms"]
]
assert len(matches) <= 1, matches
expected_support = matches[0]["support"] if matches else "unverified"
expected_state = {
    "certified": "READY",
    "limited": "LIMITED",
    "unverified": "COMPATIBILITY_UNVERIFIED",
}[expected_support]
expected_badge = {
    "READY": "MF READY",
    "LIMITED": "MF LIMITED",
    "COMPATIBILITY_UNVERIFIED": "MF UNVERIFIED",
}[expected_state]

env = {
    "HOME": str(home),
    "PATH": "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "PI_CODING_AGENT_DIR": str(agent_dir),
    "PI_OFFLINE": "1",
    "SHELL": "/bin/zsh",
    "TMPDIR": str(test_root),
}
process = subprocess.Popen(
    [
        str(node_bin),
        str(pi_bin),
        "--offline",
        "--no-session",
        "--mode", "rpc",
        "--no-context-files",
    ],
    cwd=root,
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)
events = queue.Queue()


def pump_stdout():
    try:
        for line in process.stdout:
            events.put(("event", json.loads(line)))
    except BaseException as error:
        events.put(("error", repr(error)))
    finally:
        events.put(("eof", None))


reader = threading.Thread(target=pump_stdout, name="pi-package-rpc-stdout", daemon=True)
reader.start()


def request(payload, predicate, timeout=15):
    process.stdin.write(json.dumps(payload) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        try:
            kind, event = events.get(timeout=remaining)
        except queue.Empty:
            break
        if kind == "error":
            raise AssertionError(f"Pi RPC reader failed: {event}; seen={seen}")
        if kind == "eof":
            raise AssertionError(f"Pi exited early rc={process.poll()}: {process.stderr.read()}; seen={seen}")
        seen.append(event)
        if predicate(event):
            return event, seen
    raise AssertionError(f"timed out waiting for installed Pi package; seen={seen}")


try:
    response, _ = request(
        {"type": "get_commands"},
        lambda e: e.get("type") == "response" and e.get("command") == "get_commands",
    )
    commands = response["data"]["commands"]
    mainframe = next((c for c in commands if c.get("name") == "mainframe"), None)
    skill = next((c for c in commands if c.get("name") == "skill:mainframe"), None)
    assert mainframe is not None, commands
    assert skill is not None, commands
    assert mainframe["source"] == "extension", mainframe
    assert mainframe["sourceInfo"] == {
        "path": str(root / "skills" / "pi" / "extensions" / "mainframe.ts"),
        "source": str(root),
        "scope": "user",
        "origin": "package",
        "baseDir": str(root),
    }, mainframe
    assert skill["source"] == "skill", skill
    assert skill["sourceInfo"] == {
        "path": str(root / "skills" / "pi" / "SKILL.md"),
        "source": str(root),
        "scope": "user",
        "origin": "package",
        "baseDir": str(root),
    }, skill

    status_response, status_events = request(
        {"type": "prompt", "message": "/mainframe status"},
        lambda e: e.get("type") == "response" and e.get("command") == "prompt",
    )
    assert status_response["success"] is True, status_response
    notices = [e.get("message", "") for e in status_events if e.get("method") == "notify"]
    assert any(
        f"MAINFRAME + Pi: {expected_state}" in message
        and f"{pi_manifest['name']} {pi_manifest['version']} ({expected_support.upper()})" in message
        and "disk=ready" in message
        and "gate=10.2.0:43" in message
        and "tools=7/7 effective (present=7, active=7, canonical=7; proof=verified)" in message
        for message in notices
    ), notices
    status_badges = [
        event for event in status_events
        if event.get("type") == "extension_ui_request"
        and event.get("method") == "setStatus"
        and event.get("statusKey") == "mainframe"
    ]
    assert any(event.get("statusText") == expected_badge for event in status_badges), status_badges

    doctor_response, doctor_events = request(
        {"type": "prompt", "message": "/mainframe doctor"},
        lambda e: e.get("type") == "response" and e.get("command") == "prompt",
    )
    assert doctor_response["success"] is True, doctor_response
    doctor_notices = [e.get("message", "") for e in doctor_events if e.get("method") == "notify"]
    assert any(
        f"MAINFRAME + Pi: {expected_state}" in message
        and f"Compatibility: {expected_support.upper()}" in message
        and "Runtime:     extension loaded; command 1/1; tools 7/7 effective (present=7, active=7, canonical=7, proof=verified); hooks 3/3" in message
        and "Safety gate: verified 10.2.0 (43 ordered rules)" in message
        and "Core shell doctor: exit=0 (passed)" in message
        for message in doctor_notices
    ), doctor_notices
    doctor_badges = [
        event for event in doctor_events
        if event.get("type") == "extension_ui_request"
        and event.get("method") == "setStatus"
        and event.get("statusKey") == "mainframe"
    ]
    assert any(event.get("statusText") == expected_badge for event in doctor_badges), doctor_badges

    if rpc_user_bash:
        runtime, _ = request(
            {"id": "installed-runtime", "type": "bash", "command": "declare -F json_object >/dev/null && type -P mainframe >/dev/null && printf installed-package-ok"},
            lambda e: e.get("id") == "installed-runtime" and e.get("type") == "response",
        )
        assert runtime["data"]["exitCode"] == 0, runtime
        assert runtime["data"]["output"] == "installed-package-ok", runtime

        deny_command = f"op=rm; $op -r -f -- {shlex.quote(str(sentinel_dir))}"
        denied, _ = request(
            {"id": "installed-deny-canary", "type": "bash", "command": deny_command},
            lambda e: e.get("id") == "installed-deny-canary" and e.get("type") == "response",
        )
        assert denied["data"]["exitCode"] == 126, denied
        assert "dynamic-executable-word" in denied["data"]["output"], denied
        assert sentinel_dir.is_dir(), "blocked destructive command removed the private sentinel directory"
        assert stat.S_IMODE(sentinel_dir.stat().st_mode) == 0o700, "private sentinel directory mode changed"
        assert sentinel_path.is_file(), "blocked destructive command removed the private sentinel file"
        assert stat.S_IMODE(sentinel_path.stat().st_mode) == 0o600, "private sentinel file mode changed"
        sentinel_after = sentinel_path.read_bytes()
        assert sentinel_after == sentinel_content, "blocked destructive command changed sentinel content"
        assert hashlib.sha256(sentinel_after).hexdigest() == sentinel_digest, "blocked destructive command changed sentinel digest"

        for lifecycle_id, (lifecycle_command, lifecycle_reason) in {
            "installed-remove": ("mainframe pi remove --yes", "pi-lifecycle-human-confirmation-required"),
            "installed-restore": ("mainframe pi restore --backup-id .mainframe-pi-backup-20260812T162516Z.Ab12Cd --yes", "pi-lifecycle-human-confirmation-required"),
            "installed-shell-repair": ("mainframe shell repair --shell all --yes", "mainframe-shell-lifecycle-human-terminal-required"),
        }.items():
            lifecycle, _ = request(
                {"id": lifecycle_id, "type": "bash", "command": lifecycle_command},
                lambda e, expected=lifecycle_id: e.get("id") == expected and e.get("type") == "response",
            )
            assert lifecycle["data"]["exitCode"] == 126, lifecycle
            assert lifecycle_reason in lifecycle["data"]["output"], lifecycle
            assert settings_path.read_text(encoding="utf-8") == settings_before, "installed Pi package allowed lifecycle mutation"
            assert receipt_path.read_text(encoding="utf-8") == receipt_before, "installed Pi lifecycle changed its receipt"
finally:
    process.stdin.close()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
    reader.join(timeout=2)
    assert not reader.is_alive(), "Pi package RPC stdout reader did not stop"
    stderr = process.stderr.read()
    assert process.returncode == 0, f"Pi shutdown rc={process.returncode}: {stderr}"

print("Pi local-package discovery contract passes")
PY

    [[ "$status" -eq 0 ]]
    [[ "$output" == "Pi local-package discovery contract passes" ]]
}

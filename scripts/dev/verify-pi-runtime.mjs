#!/usr/bin/env node
/** Exercise the installed native Pi SDK without a model request or live settings edits. */
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { privatePath, receiptPath, REQUIRED_CHECKS, runtimeSnapshot, verifyLocalReceipt } from "../../skills/pi/runtime-verification.mjs";

const root = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), "../.."));
const args = process.argv.slice(2);
if (args.length === 1 && ["--help", "-h"].includes(args[0])) {
  process.stdout.write("Usage: node scripts/dev/verify-pi-runtime.mjs /absolute/path/to/pi [--write-receipt]\n\nRuns native SDK checks in a private temporary project without a model request or live settings changes.\n--write-receipt saves successful exact-runtime evidence under the private Mainframe state directory.\n");
  process.exit(0);
}
const piArgument = args.find((arg) => !arg.startsWith("--"));
assert(piArgument, "Usage: node scripts/dev/verify-pi-runtime.mjs /absolute/path/to/pi [--write-receipt]");
assert(args.every((arg) => arg === piArgument || arg === "--write-receipt"), "Unknown argument");
const piCli = realpathSync(piArgument);
assert.match(piCli, /\/dist\/(?:bundle\/)?cli\.js$/);
const piRoot = piCli.replace(/\/dist\/(?:bundle\/)?cli\.js$/, "");
const manifest = JSON.parse(readFileSync(join(piRoot, "package.json"), "utf8"));
assert.equal(realpathSync(join(piRoot, typeof manifest.bin === "string" ? manifest.bin : manifest.bin.pi)), piCli);
const platform = `${process.platform === "linux" ? "Linux" : process.platform === "darwin" ? "Darwin" : process.platform}-${process.arch === "x64" ? "x86_64" : process.arch}-${process.platform === "darwin" ? "none" : process.report.getReport().header.glibcVersionRuntime ? "glibc" : "unknown"}`;
const identity = { cli: piCli, packageRoot: piRoot, package: manifest.name, version: manifest.version, platform };
const destination = receiptPath();
const snapshot = runtimeSnapshot(root, identity);
const workspace = realpathSync(mkdtempSync(join(tmpdir(), "mainframe-pi-verify-")));
const priorState = process.env.XDG_STATE_HOME;
const priorAgent = process.env.PI_CODING_AGENT_DIR;
const agentDir = join(workspace, "agent");
const project = join(workspace, "project");
for (const path of [agentDir, project, join(workspace, "state")]) mkdirSync(path, { mode: 0o700 });
process.env.PI_CODING_AGENT_DIR = agentDir;
process.env.XDG_STATE_HOME = join(workspace, "state");
process.argv[1] = piCli;
writeFileSync(join(agentDir, "settings.json"), JSON.stringify({ packages: [root] }), { mode: 0o600 });
const git = spawnSync("/usr/bin/git", ["init", "-q", project], { encoding: "utf8" });
assert.equal(git.status, 0, git.stderr);
const checks = {};
const passed = (name) => { checks[name] = "passed"; process.stderr.write(`PASS ${name}\n`); };
let session;
try {
  const sdk = await import(pathToFileURL(join(piRoot, "dist", "index.js")).href);
  const startSession = async () => {
    const settingsManager = sdk.SettingsManager.create(project, agentDir);
    const resourceLoader = new sdk.DefaultResourceLoader({ cwd: project, agentDir, settingsManager,
      noContextFiles: true, noPromptTemplates: true, noThemes: true });
    await resourceLoader.reload();
    const loaded = resourceLoader.getExtensions();
    assert.deepEqual(loaded.errors, [], "native loader errors");
    assert.equal(loaded.extensions.length, 1);
    assert.equal(realpathSync(loaded.extensions[0].path), join(root, "skills/pi/extensions/mainframe.ts"));
    assert(resourceLoader.getSkills().skills.some((skill) => skill.name === "mainframe"));
    const created = await sdk.createAgentSession({ cwd: project, agentDir, resourceLoader,
      settingsManager, sessionManager: sdk.SessionManager.inMemory(project) });
    return created.session;
  };
  session = await startSession();
  passed("native-package-discovery");
  const inventory = session.getAllTools().filter((tool) => tool.name.startsWith("mainframe_"));
  assert.equal(inventory.length, 7);
  assert(inventory.every((tool) => tool.sourceInfo?.source === root && tool.sourceInfo?.origin === "package"));
  passed("seven-tools");
  const invoke = async (name, params, signal) => {
    const tool = session.agent.state.tools.find((item) => item.name === name);
    assert(tool, `Missing active tool ${name}`);
    return tool.execute(`verify-${name}`, params, signal);
  };
  const initialStatus = await invoke("mainframe_status", {});
  assert(initialStatus.details?.piRuntime?.runtime?.gate, "Gate failed to load; synchronize the policy digest before verification");
  const prompted = await session.extensionRunner.emitBeforeAgentStart("verification", undefined,
    { cwd: project, customPrompt: "MAINFRAME_VERIFICATION_BASE" });
  assert(prompted.systemPromptOptions.forceSystemPrompt.includes("MAINFRAME_VERIFICATION_BASE"));
  assert(prompted.systemPromptOptions.forceSystemPrompt.includes("Native write/edit"));
  passed("prompt-preserved");
  const dangerous = [
    "git reset --hard", "git reset --hard;", "git reset --hard\\n", "git reset --hard HEAD",
    "git reset HEAD --hard", "git -C /tmp reset --hard", "git -c core.quotePath=false reset --hard",
    "bash <<< 'git reset --hard'", "bash <<'EOF'\ngit reset --hard\nEOF",
    "command git reset --hard", "/usr/bin/git reset --hard",
  ].map((command) => command.replace(/\\n/g, "\n"));
  for (const command of dangerous) {
    const blocked = await session.extensionRunner.emitToolCall({ type: "tool_call", toolName: "bash",
      toolCallId: "verify-block", input: { command } });
    assert.equal(blocked?.block, true, `Agent shell bypass: ${command}`);
  }
  passed("agent-shell-gate");
  // This is the native user_bash dispatch used by the TUI/RPC command handlers.
  const userShell = async (command, signal) => {
    const event = await session.extensionRunner.emitUserBash({ type: "user_bash", command, excludeFromContext: true, cwd: project });
    if (event?.result) return event.result;
    assert(event?.operations, "No shell operations from native user_bash hook");
    let output = "";
    const result = await event.operations.exec(command, project, { signal,
      onData: (chunk) => { output += chunk.toString(); } });
    return { ...result, output };
  };
  for (const command of dangerous) assert.equal((await userShell(command)).exitCode, 126, `User shell bypass: ${command}`);
  passed("user-shell-gate");
  const safeInput = { command: "printf mainframe-native-safe", timeout: 10 };
  const hook = await session.extensionRunner.emitToolCall({ type: "tool_call", toolName: "bash", toolCallId: "verify-safe", input: safeInput });
  assert(!hook?.block, JSON.stringify(hook));
  const safe = await invoke("bash", safeInput);
  assert.equal(safe.content.map((part) => part.text || "").join(""), "mainframe-native-safe");
  assert.equal((await userShell("printf mainframe-user-safe")).output, "mainframe-user-safe");
  passed("safe-shell-execution");
  const abort = new AbortController();
  const startedAt = Date.now();
  const running = userShell("sleep 30", abort.signal);
  const processTable = () => {
    const ps = spawnSync("/bin/ps", ["-axo", "pid=,ppid=,stat="], { encoding: "utf8" });
    assert.equal(ps.status, 0, ps.stderr);
    return ps.stdout.trim().split("\n").map((line) => line.trim().split(/\s+/)).map(([pid, ppid, state]) => ({ pid: Number(pid), ppid: Number(ppid), state }));
  };
  await new Promise((resolve) => setTimeout(resolve, 300));
  const beforeCancel = processTable();
  const children = new Set([process.pid]);
  for (let iteration = 0; iteration < 10; iteration++) for (const entry of beforeCancel) if (children.has(entry.ppid)) children.add(entry.pid);
  children.delete(process.pid);
  // ps itself has exited; retain only living observed descendants of this verifier.
  const liveBefore = processTable();
  const runningChildren = [...children].filter((pid) => liveBefore.some((entry) => entry.pid === pid && !entry.state.startsWith("Z")));
  assert(runningChildren.length > 0, "Cancellation check did not observe a running child");
  abort.abort();
  let cancelled = false;
  try { const result = await running; cancelled = result.exitCode !== 0; }
  catch (error) { assert.match(String(error), /abort|cancel/i); cancelled = true; }
  assert(cancelled, "Cancelled shell reported success");
  assert(Date.now() - startedAt < 5_000, "Cancelled shell did not stop promptly");
  await new Promise((resolve) => setTimeout(resolve, 100));
  const afterCancel = processTable();
  assert(!runningChildren.some((pid) => afterCancel.some((entry) => entry.pid === pid && !entry.state.startsWith("Z"))), "Cancelled shell left a live descendant");
  passed("cancellation");
  const initialized = await invoke("mainframe_awm", { scope: "project", action: "init", name: "pi-native-verification" });
  assert.equal(initialized.details?.status, "ok", JSON.stringify(initialized));
  const value = "First line\nSecond line\n\n";
  const checkpoint = await invoke("mainframe_awm", { scope: "project", action: "checkpoint", key: "resume", value });
  assert.equal(checkpoint.details?.status, "ok", JSON.stringify(checkpoint));
  session.dispose();
  session = await startSession();
  const preAborted = new AbortController(); preAborted.abort();
  const skipped = await invoke("mainframe_awm", { scope: "project", action: "checkpoint", key: "resume", value: "must-not-write" }, preAborted.signal);
  assert.equal(skipped.details?.status, "unavailable");
  const restored = await invoke("mainframe_awm", { scope: "project", action: "get", key: "resume", value: true });
  assert.equal(restored.details?.status, "ok", JSON.stringify(restored));
  const framed = restored.content.map((part) => part.text || "").join("");
  const data = framed.match(/<mainframe-project-memory-data>\n(.*?)\n<\/mainframe-project-memory-data>/s);
  assert(data, JSON.stringify(restored));
  assert.equal(JSON.parse(data[1]).value, value, JSON.stringify(restored));
  passed("project-checkpoint-restart");
  const status = await invoke("mainframe_status", {});
  assert.deepEqual(status.details?.piRuntime?.protectionBoundary?.outsideGate, ["write", "edit", "other-extension-tools"]);
  assert.equal(status.details?.piRuntime?.runtime?.toolProof?.ready, true, JSON.stringify(status));
  assert.equal(status.details?.piRuntime?.identity?.cli, piCli);
  passed("status-boundary");
  assert.deepEqual(Object.keys(checks).sort(), [...REQUIRED_CHECKS].sort());
  assert.deepEqual(runtimeSnapshot(root, identity), snapshot, "Runtime changed during verification; repeat after changes finish");
  const receipt = { schema: 1, kind: "mainframe-pi-local-verification", verifiedAt: new Date().toISOString(),
    checks, snapshot, limitations: ["Native SDK checks do not certify an already-running Pi session or render the TUI.",
      "Native write/edit and other extension tools are outside the shell gate.", "No upstream compatibility or release certification is implied."] };
  if (priorState === undefined) delete process.env.XDG_STATE_HOME; else process.env.XDG_STATE_HOME = priorState;
  if (args.includes("--write-receipt")) {
    const directory = dirname(destination);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    assert(privatePath(directory), "Receipt directory must be private, owned, and free of unsafe ancestors");
    if (existsSync(destination)) assert(privatePath(destination, true), "Existing receipt is not a private regular file");
    const temporary = join(directory, `.runtime-verification-${process.pid}.json`);
    writeFileSync(temporary, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600, flag: "wx" });
    renameSync(temporary, destination);
    assert(verifyLocalReceipt(root, identity), "Written receipt failed validation");
    const verifiedStatus = await invoke("mainframe_status", {});
    assert.equal(verifiedStatus.details?.piRuntime?.state, "local-verified", JSON.stringify(verifiedStatus));
    process.stderr.write("PASS in-process LOCAL_VERIFIED (isolated native SDK session)\n");
  }
  process.stdout.write(`${JSON.stringify({ ...receipt, receiptPath: args.includes("--write-receipt") ? destination : null }, null, 2)}\n`);
} finally {
  session?.dispose();
  if (priorState === undefined) delete process.env.XDG_STATE_HOME; else process.env.XDG_STATE_HOME = priorState;
  if (priorAgent === undefined) delete process.env.PI_CODING_AGENT_DIR; else process.env.PI_CODING_AGENT_DIR = priorAgent;
  rmSync(workspace, { recursive: true, force: true });
}

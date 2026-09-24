import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

const discovered = process.env.MAINFRAME_PI_BIN || spawnSync("/bin/sh", ["-c", "command -v pi"], { encoding: "utf8" }).stdout.trim();
let processRunner;
async function loadRunProcess() {
  if (processRunner) return processRunner;
  const piCli = realpathSync(discovered);
  const require = createRequire(piCli);
  const { createJiti } = require("jiti");
  const jiti = createJiti(import.meta.url, { moduleCache: false, fsCache: false,
    alias: { typebox: require.resolve("typebox") } });
  const { runProcess } = await jiti.import(new URL("../skills/pi/extensions/mainframe.ts", import.meta.url).pathname);
  processRunner = runProcess;
  return runProcess;
}

function liveGroup(groupId) {
  const ps = spawnSync("/bin/ps", ["-axo", "pid=,pgid=,stat="], { encoding: "utf8" });
  assert.equal(ps.status, 0);
  return ps.stdout.trim().split("\n").map((line) => line.trim().split(/\s+/))
    .filter(([, group, state]) => Number(group) === groupId && !state.startsWith("Z"));
}

async function awaitPid(path) {
  for (let attempt = 0; attempt < 100 && !existsSync(path); attempt++) await delay(20);
  assert(existsSync(path), "fixture process did not start");
  const pid = Number(readFileSync(path, "utf8").trim());
  assert(pid > 1);
  return pid;
}

test("Pi subprocess cancellation escalates TERM-resistant groups and skips pre-aborted calls", { skip: !discovered }, async () => {
  const runProcess = await loadRunProcess();
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-process-"));
  let pid;
  try {
    const sentinel = join(workspace, "must-not-exist");
    const alreadyAborted = new AbortController(); alreadyAborted.abort();
    const skipped = await runProcess("/bin/bash", ["-c", 'printf spawned > "$1"', "check", sentinel], { signal: alreadyAborted.signal });
    assert.equal(skipped.signal, "SIGTERM");
    assert(!existsSync(sentinel));

    const pidPath = join(workspace, "child.pid");
    const abort = new AbortController();
    const running = runProcess("/bin/bash", ["--noprofile", "--norc", "-c",
      'trap "" TERM; printf "%s\\n" "$$" > "$1"; while :; do sleep 1; done', "resistant-child", pidPath],
      { signal: abort.signal, timeoutMs: 30_000 });
    pid = await awaitPid(pidPath);
    const started = Date.now(); abort.abort();
    const result = await running;
    assert.equal(result.signal, "SIGKILL", JSON.stringify(result));
    assert.equal(result.timedOut, false, "abort relied on the 30s command timeout");
    assert(Date.now() - started < 5_000, "escalation was not bounded");
    assert.deepEqual(liveGroup(pid), [], "cancellation left a live process in the group");
    pid = undefined;
  } finally {
    if (pid) { try { process.kill(-pid, "SIGKILL"); } catch {} }
    rmSync(workspace, { recursive: true, force: true });
  }
});

test("Pi cancellation cleans detached-output descendants after their leader exits", { skip: !discovered }, async () => {
  const runProcess = await loadRunProcess();
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-descendant-"));
  let pid;
  try {
    const leaderPath = join(workspace, "leader.pid");
    const childPath = join(workspace, "child.pid");
    const script = `const fs=require('node:fs'); const {spawn}=require('node:child_process');
      fs.writeFileSync(process.argv[1],String(process.pid));
      spawn('/bin/bash',['--noprofile','--norc','-c','trap "" TERM; printf "%s\\n" "$$" > "$1"; while :; do sleep 1; done','resistant-descendant',process.argv[2]],{stdio:'ignore'});
      setInterval(()=>{},1000);`;
    const abort = new AbortController();
    const running = runProcess(process.execPath, ["-e", script, leaderPath, childPath], { signal: abort.signal, timeoutMs: 10_000 });
    pid = await awaitPid(leaderPath); await awaitPid(childPath);
    abort.abort();
    const result = await running;
    assert.equal(result.signal, "SIGTERM");
    await delay(100);
    assert.deepEqual(liveGroup(pid), [], "cancelled leader left a TERM-resistant descendant alive");
    pid = undefined;
  } finally {
    if (pid) { try { process.kill(-pid, "SIGKILL"); } catch {} }
    rmSync(workspace, { recursive: true, force: true });
  }
});

for (const stream of ["stdout", "stderr"]) test(`Pi ${stream} capture overflow escalates without waiting for the ordinary timeout`, { skip: !discovered }, async () => {
  const runProcess = await loadRunProcess();
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-overflow-"));
  let pid;
  try {
    const pidPath = join(workspace, "child.pid");
    const started = Date.now();
    const result = await runProcess("/bin/bash", ["--noprofile", "--norc", "-c",
      `trap "" TERM; printf "%s\\n" "$$" > "$1"; printf "%4096s" x${stream === "stderr" ? " >&2" : ""}; while :; do sleep 1; done`, "overflow-child", pidPath],
      { captureLimitBytes: 100, timeoutMs: 6_000 });
    pid = await awaitPid(pidPath);
    assert.equal(result.timedOut, false, "capture overflow waited for the ordinary timeout");
    assert(Date.now() - started < 5_000, "capture overflow termination was not bounded");
    assert.equal(result.stdout, "");
    assert.deepEqual(liveGroup(pid), [], "capture overflow left a live process in the group");
    pid = undefined;
  } finally {
    if (pid) { try { process.kill(-pid, "SIGKILL"); } catch {} }
    rmSync(workspace, { recursive: true, force: true });
  }
});

for (const scenario of ["timeout", "rejected-cancel", "unresolved-cancel"]) test(`Pi ${scenario} supervision still terminates a resistant process group`, { skip: !discovered }, async () => {
  const runProcess = await loadRunProcess();
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-stop-fallback-"));
  let pid;
  try {
    const pidPath = join(workspace, "child.pid");
    const abort = new AbortController();
    let cancelCalls = 0;
    const cancel = scenario === "timeout" ? undefined : () => {
      cancelCalls++;
      return scenario === "rejected-cancel" ? Promise.reject(new Error("fixture cancellation refused")) : new Promise(() => {});
    };
    const started = Date.now();
    const running = runProcess("/bin/bash", ["--noprofile", "--norc", "-c",
      'trap "" TERM; printf "%s\\n" "$$" > "$1"; while :; do sleep 1; done', "fallback-child", pidPath],
      { signal: abort.signal, timeoutMs: scenario === "timeout" ? 1_000 : 10_000, cancel });
    pid = await awaitPid(pidPath);
    if (scenario !== "timeout") { abort.abort(); abort.abort(); }
    const result = await running;
    assert.equal(result.signal, "SIGKILL");
    assert.equal(result.timedOut, scenario === "timeout");
    assert.equal(cancelCalls, scenario === "timeout" ? 0 : 1, "cancellation callback was repeated");
    assert(Date.now() - started < 5_000, "cancellation fallback was not bounded");
    assert.deepEqual(liveGroup(pid), [], "fallback left a live process in the group");
    pid = undefined;
  } finally {
    if (pid) { try { process.kill(-pid, "SIGKILL"); } catch {} }
    rmSync(workspace, { recursive: true, force: true });
  }
});

test("Pi process errors and early stdin refusal remain bounded results", { skip: !discovered }, async () => {
  const runProcess = await loadRunProcess();
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-errors-"));
  try {
    const missing = await runProcess(join(workspace, "missing-executable"), [], { cwd: workspace });
    assert.equal(missing.code, 127); assert.match(missing.stderr, /ENOENT/);
    const refused = await runProcess("/bin/bash", ["--noprofile", "--norc", "-c", "printf refused >&2; exit 65"],
      { input: "x".repeat(1_000_000), cwd: workspace });
    assert.equal(refused.code, 65); assert.match(refused.stderr, /refused/);
    assert.equal(refused.timedOut, false);
  } finally { rmSync(workspace, { recursive: true, force: true }); }
});

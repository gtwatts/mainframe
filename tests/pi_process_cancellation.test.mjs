import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";

const discovered = process.env.MAINFRAME_PI_BIN || spawnSync("/bin/sh", ["-c", "command -v pi"], { encoding: "utf8" }).stdout.trim();
test("Pi subprocess cancellation escalates TERM-resistant groups and skips pre-aborted calls", { skip: !discovered }, async () => {
  const piCli = realpathSync(discovered);
  const require = createRequire(piCli);
  const { createJiti } = require("jiti");
  const jiti = createJiti(import.meta.url, { moduleCache: false, fsCache: false,
    alias: { typebox: require.resolve("typebox") } });
  const { runProcess } = await jiti.import(new URL("../skills/pi/extensions/mainframe.ts", import.meta.url).pathname);
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
    for (let attempt = 0; attempt < 100 && !existsSync(pidPath); attempt++) await delay(20);
    assert(existsSync(pidPath), "fixture process did not start");
    pid = Number(readFileSync(pidPath, "utf8").trim());
    assert(pid > 1);
    const started = Date.now(); abort.abort();
    const result = await running;
    assert.equal(result.signal, "SIGKILL", JSON.stringify(result));
    assert.equal(result.timedOut, false, "abort relied on the 30s command timeout");
    assert(Date.now() - started < 5_000, "escalation was not bounded");
    const ps = spawnSync("/bin/ps", ["-axo", "pid=,pgid=,stat="], { encoding: "utf8" });
    assert.equal(ps.status, 0);
    const liveGroup = ps.stdout.trim().split("\n").map((line) => line.trim().split(/\s+/))
      .filter(([, group, state]) => Number(group) === pid && !state.startsWith("Z"));
    assert.deepEqual(liveGroup, [], "cancellation left a live process in the group");
    pid = undefined;
  } finally {
    if (pid) { try { process.kill(-pid, "SIGKILL"); } catch {} }
    rmSync(workspace, { recursive: true, force: true });
  }
});

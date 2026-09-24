import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { REQUIRED_CHECKS, receiptPath, runtimeSnapshot, verifyLocalReceipt } from "../skills/pi/runtime-verification.mjs";

test("local runtime evidence rejects stale source, dependencies, incomplete checks and unsafe receipts", () => {
  const workspace = mkdtempSync(join(tmpdir(), "mainframe-pi-receipt-test-"));
  const prior = process.env.XDG_STATE_HOME;
  process.env.XDG_STATE_HOME = join(workspace, "state");
  try {
    const root = join(workspace, "mainframe");
    const piRoot = join(workspace, "consumer/node_modules/pi");
    for (const name of ["bin", "lib", "security", "hooks", "control_plane", "skills/pi", "config", "scripts/dev"]) {
      mkdirSync(join(root, name), { recursive: true, mode: 0o700 });
    }
    for (const name of ["package.json", "VERSION", "FUNCTIONS.json", "MANIFEST.json", "INVOCATION_INDEX.json", "scripts/dev/verify-pi-runtime.mjs"]) {
      writeFileSync(join(root, name), "fixture\n", { mode: 0o600 });
    }
    mkdirSync(piRoot, { recursive: true, mode: 0o700 });
    const dependency = join(piRoot, "runtime.js");
    writeFileSync(dependency, "original\n", { mode: 0o600 });
    const identity = { cli: join(piRoot, "dist/cli.js"), packageRoot: piRoot, package: "pi", version: "1.0.0", platform: "test" };
    const receipt = { schema: 1, kind: "mainframe-pi-local-verification", verifiedAt: new Date().toISOString(),
      checks: Object.fromEntries(REQUIRED_CHECKS.map((name) => [name, "passed"])), snapshot: runtimeSnapshot(root, identity) };
    const path = receiptPath();
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    const save = () => writeFileSync(path, JSON.stringify(receipt), { mode: 0o600 });
    save();
    assert(verifyLocalReceipt(root, identity));
    assert.equal(verifyLocalReceipt(root, { ...identity, version: "1.0.1" }), null);
    writeFileSync(dependency, "modified\n");
    assert.equal(verifyLocalReceipt(root, identity), null);
    writeFileSync(dependency, "original\n");
    assert(verifyLocalReceipt(root, identity));
    writeFileSync(join(root, "lib/new.sh"), "new runtime\n");
    assert.equal(verifyLocalReceipt(root, identity), null);
    rmSync(join(root, "lib/new.sh"));
    receipt.checks.cancellation = "skipped"; save();
    assert.equal(verifyLocalReceipt(root, identity), null);
    receipt.checks.cancellation = "passed"; save();
    chmodSync(path, 0o644);
    assert.equal(verifyLocalReceipt(root, identity), null);
    chmodSync(path, 0o600);
    assert(verifyLocalReceipt(root, identity));
    const copy = join(workspace, "receipt-copy.json");
    writeFileSync(copy, readFileSync(path), { mode: 0o600 });
    rmSync(path); symlinkSync(copy, path);
    assert.equal(verifyLocalReceipt(root, identity), null);
  } finally {
    if (prior === undefined) delete process.env.XDG_STATE_HOME; else process.env.XDG_STATE_HOME = prior;
    rmSync(workspace, { recursive: true, force: true });
  }
});

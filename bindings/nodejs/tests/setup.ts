/** Isolate durable control-plane state from developer and prior-schema ledgers. */

import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const previousStateHome = process.env.XDG_STATE_HOME;
const stateHome = realpathSync(mkdtempSync(join(tmpdir(), "mainframe-node-state-")));
chmodSync(stateHome, 0o700);
process.env.XDG_STATE_HOME = stateHome;

// Each assertion gets a fresh durable ledger and worker-lock directory. Calls
// within one assertion still share state, so replay and correlation behavior
// remain covered without making later assertions pay for every earlier call.
export const durableControlPlaneStateDirectoryForTest = join(stateHome, "mainframe");

export function prepareDurableStateForTestFile(): void {
  mkdirSync(stateHome, { recursive: true, mode: 0o700 });
  chmodSync(stateHome, 0o700);
  process.env.XDG_STATE_HOME = stateHome;
  rmSync(durableControlPlaneStateDirectoryForTest, { recursive: true, force: true });
}

export function resetDurableControlPlaneStateForTest(): void {
  prepareDurableStateForTestFile();
}

export function cleanupDurableStateForTestFile(): void {
  rmSync(stateHome, { recursive: true, force: true });
}

process.once("exit", () => {
  if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
  else process.env.XDG_STATE_HOME = previousStateHome;
  cleanupDurableStateForTestFile();
});

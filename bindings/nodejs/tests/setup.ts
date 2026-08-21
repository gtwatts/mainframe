/** Isolate durable control-plane state from developer and prior-schema ledgers. */

import { chmodSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const previousStateHome = process.env.XDG_STATE_HOME;
const stateHome = realpathSync(mkdtempSync(join(tmpdir(), "mainframe-node-state-")));
chmodSync(stateHome, 0o700);
process.env.XDG_STATE_HOME = stateHome;

process.once("exit", () => {
  if (previousStateHome === undefined) delete process.env.XDG_STATE_HOME;
  else process.env.XDG_STATE_HOME = previousStateHome;
  rmSync(stateHome, { recursive: true, force: true });
});

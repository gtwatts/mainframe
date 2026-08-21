/** Regression coverage for the durable control-plane test fixture. */

import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  durableControlPlaneStateDirectoryForTest,
  cleanupDurableStateForTestFile,
  prepareDurableStateForTestFile,
  resetDurableControlPlaneStateForTest,
} from "./setup";

const marker = join(durableControlPlaneStateDirectoryForTest, "leaked-state");

beforeAll(prepareDurableStateForTestFile);
beforeEach(resetDurableControlPlaneStateForTest);
afterAll(cleanupDurableStateForTestFile);

test("durable fixture can populate its isolated Mainframe state", () => {
  mkdirSync(durableControlPlaneStateDirectoryForTest, { recursive: true });
  writeFileSync(marker, "must not reach another test", { mode: 0o600 });
  expect(Bun.file(marker).size).toBeGreaterThan(0);
});

test("durable fixture resets Mainframe state between tests", async () => {
  expect(await Bun.file(marker).exists()).toBe(false);
});

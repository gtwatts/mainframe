/** Local evidence for one installed Pi and Mainframe, never a release certificate. */
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative } from "node:path";

export const REQUIRED_CHECKS = [
  "native-package-discovery", "seven-tools", "prompt-preserved", "agent-shell-gate",
  "user-shell-gate", "safe-shell-execution", "cancellation", "project-checkpoint-restart",
  "status-boundary",
];

export function receiptPath() {
  const base = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  if (!isAbsolute(base)) throw new Error("XDG_STATE_HOME must be absolute");
  return join(base, "mainframe", "pi", "runtime-verification.json");
}

export function privatePath(path, file = false) {
  const uid = process.getuid();
  const leaf = lstatSync(path);
  if (leaf.isSymbolicLink() || (file ? !leaf.isFile() : !leaf.isDirectory()) ||
      leaf.uid !== uid || (leaf.mode & 0o077) || (file && leaf.nlink !== 1)) return false;
  let current = dirname(path);
  while (current !== dirname(current)) {
    const meta = lstatSync(current);
    if (!meta.isDirectory() || meta.isSymbolicLink() ||
        (meta.uid !== uid && meta.uid !== 0) ||
        ((meta.mode & 0o022) && !(meta.uid === 0 && (meta.mode & 0o1000)))) return false;
    current = dirname(current);
  }
  return true;
}

function treeDigest(root, entries) {
  const hash = createHash("sha256");
  let files = 0;
  const walk = (path) => {
    const meta = lstatSync(path);
    if (meta.isSymbolicLink()) throw new Error(`Unbound symbolic link in runtime: ${path}`);
    if (meta.isDirectory()) {
      for (const name of readdirSync(path).sort()) {
        if ([".bin", "__pycache__", ".pytest_cache"].includes(name)) continue;
        walk(join(path, name));
      }
    } else if (meta.isFile()) {
      hash.update(relative(root, path)); hash.update("\0");
      hash.update(String(meta.mode & 0o777)); hash.update("\0");
      hash.update(readFileSync(path)); hash.update("\0"); files++;
    } else throw new Error(`Unsupported runtime file: ${path}`);
  };
  for (const entry of entries) walk(join(root, entry));
  return { sha256: hash.digest("hex"), files };
}

export function runtimeSnapshot(root, identity) {
  const mainframeRoot = realpathSync(root);
  const piRoot = realpathSync(identity.packageRoot);
  const marker = piRoot.lastIndexOf("/node_modules/");
  if (marker < 0) throw new Error("Local verification requires an installed npm dependency closure");
  const dependencies = piRoot.slice(0, marker + "/node_modules".length);
  return {
    mainframe: {
      root: mainframeRoot,
      version: readFileSync(join(root, "VERSION"), "utf8").trim(),
      ...treeDigest(mainframeRoot, ["bin", "lib", "security", "hooks", "control_plane", "skills/pi", "config", "scripts",
        "package.json", "VERSION", "FUNCTIONS.json", "MANIFEST.json", "INVOCATION_INDEX.json"]),
    },
    pi: { ...identity, dependencyRoot: dependencies, ...treeDigest(dependencies, ["."]) },
    node: { executable: realpathSync(process.execPath), version: process.version,
      sha256: createHash("sha256").update(readFileSync(process.execPath)).digest("hex") },
  };
}

export function verifyLocalReceipt(root, identity) {
  try {
    const path = receiptPath();
    if (!identity || !privatePath(path, true) || lstatSync(path).size > 64_000) return null;
    const receipt = JSON.parse(readFileSync(path, "utf8"));
    if (receipt.schema !== 1 || receipt.kind !== "mainframe-pi-local-verification" ||
        !Number.isFinite(Date.parse(receipt.verifiedAt)) ||
        !REQUIRED_CHECKS.every((check) => receipt.checks?.[check] === "passed")) return null;
    const snapshot = runtimeSnapshot(root, identity);
    if (JSON.stringify(receipt.snapshot) !== JSON.stringify(snapshot)) return null;
    return { path, verifiedAt: receipt.verifiedAt, checks: receipt.checks, scope: "local-runtime-only",
      snapshotSha256: createHash("sha256").update(JSON.stringify(snapshot)).digest("hex") };
  } catch { return null; }
}

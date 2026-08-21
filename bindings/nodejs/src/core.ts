/**
 * MAINFRAME Node.js Bindings - Core Module
 *
 * Provides subprocess wrapper for calling MAINFRAME bash functions
 * with proper error handling and USOP JSON response parsing.
 */

import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import {
  accessSync,
  constants,
  lstatSync,
  readFileSync,
  realpathSync,
  statSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";

// =============================================================================
// Types
// =============================================================================

/** USOP (Universal Structured Output Protocol) envelope */
export interface UsopEnvelope<T = unknown> {
  ok: boolean;
  data?: T;
  error?: string;
  meta?: {
    duration_ms?: number;
    function?: string;
    timestamp?: string;
  };
  hint?: string;
}

/** Result type for MAINFRAME function calls */
export type MainframeResult<T> =
  | { success: true; data: T; raw: string }
  | { success: false; error: string; raw: string };

/** Exact wire envelope returned by `mainframe invoke --format broker-json-v1`. */
export interface BrokerEnvelopeV1 {
  schema_version: 1;
  ok: boolean;
  status: string;
  canonical_id: string;
  name: string | null;
  owner: string | null;
  exit_code: number;
  timed_out: boolean;
  output_exceeded: boolean;
  duration_ms: number;
  audit_id: string;
  stdout_b64: string;
  stderr_b64: string;
  error: string | null;
}

/** Durable metadata-only receipt bound to the validated broker envelope. */
export interface BrokerReceiptV1 {
  schema_version: 1;
  ok: boolean;
  status: string;
  canonical_id: string;
  name: string;
  owner: string;
  exit_code: number;
  timed_out: boolean;
  output_exceeded: boolean;
  duration_ms: number;
  audit_id: string;
  stdout_bytes: number;
  stdout_sha256: string;
  stderr_bytes: number;
  stderr_sha256: string;
  error_bytes: number;
  error_sha256: string;
}

/** Exact durable result returned by control-plane-json-v1. */
export interface ControlPlaneInvocationV1 {
  schemaVersion: 1;
  status: "in_progress" | "completed";
  clientCorrelationId: string;
  runId: string;
  callId: string;
  decisionId: string;
  evidenceId: string | null;
  inputDigest: string;
  outcome: "succeeded" | "failed" | "timed_out" | "interrupted" | null;
  resultAvailable: boolean;
  brokerReceipt: BrokerReceiptV1 | null;
}

/** Decoded result from a canonical broker invocation. */
export interface BrokerInvocationResult {
  controlPlane: ControlPlaneInvocationV1;
  envelope: BrokerEnvelopeV1 | null;
  resultKind: "stdout" | "exit" | "none";
  stdout: string;
  stderr: string;
  raw: string;
}

/** Per-call controls for the canonical broker adapter. */
export interface BrokerInvokeOptions {
  /**
   * Additional child-process variables. Root selection is configuration-only:
   * MAINFRAME_ROOT here is overwritten by the authoritative environment,
   * setConfig root, or automatically detected installation.
   */
  env?: Record<string, string>;
  timeout?: number;
  cwd?: string;
}

/** Configuration options for MAINFRAME */
export interface MainframeConfig {
  /** Path to MAINFRAME root directory */
  mainframeRoot: string;
  /** Output mode: 'raw' | 'json' | 'minimal' | 'debug' */
  outputMode: "raw" | "json" | "minimal" | "debug";
  /** Timeout in milliseconds for bash execution */
  timeout: number;
  /** Shell to use (default: automatically resolved Bash 4.4+ executable) */
  shell: string;
}

// =============================================================================
// Configuration
// =============================================================================

/**
 * Resolve a Bash 4.4+ executable.
 *
 * macOS still ships /bin/bash 3.2, while MAINFRAME requires Bash 4.4+.
 * An explicit MAINFRAME_BASH override must be absolute. Otherwise only fixed
 * reviewed package-manager and system locations are checked; ambient PATH is
 * never searched.
 * The selected executable is cached by its canonical absolute path.
 */
let resolvedShell: string | null = null;
const MINIMUM_BASH_VERSION = [4, 4] as const;
/** @internal Exported only for binding conformance tests. */
export const FIXED_BASH_CANDIDATES = Object.freeze([
  "/opt/homebrew/bin/bash",
  "/usr/local/bin/bash",
  "/home/linuxbrew/.linuxbrew/bin/bash",
  "/opt/local/bin/bash",
  "/nix/var/nix/profiles/default/bin/bash",
  "/run/current-system/sw/bin/bash",
  join(homedir(), ".nix-profile", "bin", "bash"),
  "/usr/bin/bash",
  "/bin/bash",
] as const);
// Treat inherited startup hooks and exported shell functions as untrusted.
const PROTECTED_BASH_ARGS = ["--noprofile", "--norc", "-p", "-c"] as const;
const BASH_PROBE_ENV = { PATH: "/usr/bin:/bin", LC_ALL: "C" } as const;
const UNSAFE_EXECUTION_ENVIRONMENT_KEYS = new Set([
  "BASHOPTS",
  "BASH_ENV",
  "BASH_LOADABLES_PATH",
  "BASH_XTRACEFD",
  "CDPATH",
  "ENV",
  "GLOBIGNORE",
  "NODE_OPTIONS",
  "NODE_PATH",
  "NODE_REDIRECT_WARNINGS",
  "NODE_REPL_HISTORY",
  "NODE_V8_COVERAGE",
  "PERL5LIB",
  "PERL5OPT",
  "PERLLIB",
  "PYTHONBREAKPOINT",
  "PYTHONHOME",
  "PYTHONINSPECT",
  "PYTHONPATH",
  "PYTHONSTARTUP",
  "PYTHONUSERBASE",
  "PYTHONWARNINGS",
  "RUBYLIB",
  "RUBYOPT",
  "SHELLOPTS",
]);
const UNSAFE_EXECUTION_ENVIRONMENT_PREFIXES = [
  "BASH_FUNC_",
  "LD_",
  "DYLD_",
] as const;

/** @internal Pure reviewed-layout predicate used by binding conformance tests. */
export function approvedBashLayout(candidate: string): boolean {
  return (
    candidate === "/usr/bin/bash" ||
    candidate === "/bin/bash" ||
    candidate === "/usr/local/bin/bash" ||
    candidate === "/opt/local/bin/bash" ||
    /^\/(?:opt\/homebrew|usr\/local|home\/linuxbrew\/\.linuxbrew)\/Cellar\/[^/]+\/[^/]+\/bin\/bash$/.test(
      candidate,
    ) ||
    /^\/nix\/store\/[^/]+\/bin\/bash$/.test(candidate)
  );
}

function canonicalBashCandidate(candidate: string): string | null {
  if (!isAbsolute(candidate)) return null;

  try {
    const canonical = realpathSync(candidate);
    const metadata = statSync(canonical);
    const effectiveUid =
      typeof process.geteuid === "function" ? process.geteuid() : metadata.uid;
    const mode = metadata.mode & 0o7777;
    if (
      !isAbsolute(canonical) ||
      !approvedBashLayout(canonical) ||
      !metadata.isFile() ||
      (metadata.uid !== 0 && metadata.uid !== effectiveUid) ||
      (mode & 0o022) !== 0 ||
      (mode & 0o7000) !== 0 ||
      (mode & 0o100) === 0
    ) {
      return null;
    }
    accessSync(canonical, constants.X_OK);
    return canonical;
  } catch {
    return null;
  }
}

function compatibleBash(candidate: string): string | null {
  const canonical = canonicalBashCandidate(candidate);
  if (!canonical) return null;

  try {
    const probe = spawnSync(
      canonical,
      [
        ...PROTECTED_BASH_ARGS,
        "printf '%s %s\\n' \"${BASH_VERSINFO[0]}\" \"${BASH_VERSINFO[1]}\"",
      ],
      {
        encoding: "utf8",
        env: BASH_PROBE_ENV,
        timeout: 5000,
      },
    );
    const version = /^(\d+)\s+(\d+)$/.exec((probe.stdout || "").trim());
    const major = version ? Number.parseInt(version[1], 10) : 0;
    const minor = version ? Number.parseInt(version[2], 10) : 0;
    if (
      probe.status === 0 &&
      (major > MINIMUM_BASH_VERSION[0] ||
        (major === MINIMUM_BASH_VERSION[0] && minor >= MINIMUM_BASH_VERSION[1]))
    ) {
      return canonical;
    }
  } catch {
    // Candidate not executable; the caller will reject it or try the next one.
  }
  return null;
}

function protectedExecutionEnvironment(
  overrides: Record<string, string> = {},
): NodeJS.ProcessEnv {
  const environment: NodeJS.ProcessEnv = { ...process.env, ...overrides };
  for (const key of Object.keys(environment)) {
    if (
      UNSAFE_EXECUTION_ENVIRONMENT_KEYS.has(key) ||
      UNSAFE_EXECUTION_ENVIRONMENT_PREFIXES.some((prefix) => key.startsWith(prefix))
    ) {
      delete environment[key];
    }
  }
  return environment;
}

export function resolveBash(customShell?: string): string {
  if (customShell !== undefined) {
    if (!isAbsolute(customShell)) {
      throw new Error("shell must be an absolute path");
    }
    const compatible = compatibleBash(customShell);
    if (!compatible) {
      throw new Error(
        "shell must resolve to an owner-safe Bash 4.4+ approved installation layout",
      );
    }
    return compatible;
  }

  if (resolvedShell) return resolvedShell;

  const override = process.env.MAINFRAME_BASH;
  if (override) {
    if (!isAbsolute(override)) {
      throw new Error("MAINFRAME_BASH must be an absolute path");
    }
    const compatible = compatibleBash(override);
    if (!compatible) {
      throw new Error(
        "MAINFRAME_BASH must resolve to an owner-safe Bash 4.4+ approved installation layout",
      );
    }
    resolvedShell = compatible;
    return compatible;
  }

  for (const candidate of FIXED_BASH_CANDIDATES) {
    const compatible = compatibleBash(candidate);
    if (compatible) {
      resolvedShell = compatible;
      return compatible;
    }
  }

  throw new Error(
    "MAINFRAME Node.js bindings require Bash 4.4 or newer at a supported " +
      "absolute path; set MAINFRAME_BASH to an intentional trusted executable",
  );
}

type InternalMainframeConfig = Omit<MainframeConfig, "shell"> & {
  shell: string | null;
};

const DEFAULT_CONFIG: InternalMainframeConfig = {
  mainframeRoot: process.env.MAINFRAME_ROOT ?? join(homedir(), ".mainframe"),
  outputMode: "json",
  timeout: 30000,
  shell: null,
};

let config: InternalMainframeConfig = { ...DEFAULT_CONFIG };
let mainframeRootSetByConfig = false;

/*
 * Bash resolution is intentionally lazy: importing the binding does not start
 * a subprocess. The first configuration read or execution resolves the fixed
 * interpreter and every later call reuses that canonical absolute path.
 */
function configuredShell(): string {
  if (config.shell) return config.shell;
  const shell = resolveBash();
  config.shell = shell;
  return shell;
}

/**
 * Get the current MAINFRAME configuration
 */
export function getConfig(): MainframeConfig {
  return { ...config, shell: configuredShell() };
}

/**
 * Update MAINFRAME configuration
 */
export function setConfig(newConfig: Partial<MainframeConfig>): void {
  // Validate and canonicalize before publishing any part of the new config.
  const shell =
    newConfig.shell === undefined ? config.shell : resolveBash(newConfig.shell);
  const nextConfig: InternalMainframeConfig = {
    ...config,
    ...newConfig,
    shell,
  };
  config = nextConfig;
  if (newConfig.mainframeRoot !== undefined) {
    mainframeRootSetByConfig = true;
  }
}

function detectManagedLauncherRoot(): string | null {
  const launcher = join(homedir(), ".local", "bin", "mainframe");
  try {
    const target = realpathSync(launcher);
    if (
      !statSync(target).isFile() ||
      !target.endsWith("/bin/mainframe") ||
      dirname(target).split("/").pop() !== "bin"
    ) {
      return null;
    }
    accessSync(target, constants.X_OK);
    const root = dirname(dirname(target));
    return durableRootIsUsable(root) ? root : null;
  } catch {
    return null;
  }
}

/**
 * Detect MAINFRAME installation path.
 *
 * An explicitly set MAINFRAME_ROOT is authoritative: an invalid or empty
 * value fails closed instead of silently selecting another installation.
 */
export function detectMainframeRoot(): string | null {
  const configuredRoot = process.env.MAINFRAME_ROOT;
  if (configuredRoot !== undefined) {
    if (configuredRoot.length === 0) return null;
    return durableRootIsUsable(configuredRoot) ? configuredRoot : null;
  }

  const candidates = [
    detectManagedLauncherRoot(),
    join(homedir(), ".mainframe"),
    "/opt/mainframe",
    "/usr/local/mainframe",
  ].filter((p): p is string => typeof p === "string");

  for (const candidate of candidates) {
    if (durableRootIsUsable(candidate)) {
      return candidate;
    }
  }

  return null;
}

function durableRootIsUsable(candidate: string): boolean {
  try {
    const canonical = realpathSync(candidate);
    if (canonical !== resolve(candidate) || !statSync(canonical).isDirectory()) return false;
    const uid = typeof process.getuid === "function" ? process.getuid() : 0;
    for (const relative of DURABLE_CLOSURE_FILES) {
      const path = join(canonical, relative);
      const metadata = lstatSync(path);
      if (
        !metadata.isFile() ||
        metadata.isSymbolicLink() ||
        (metadata.uid !== 0 && metadata.uid !== uid) ||
        (metadata.mode & 0o022) !== 0 ||
        metadata.nlink !== 1 ||
        metadata.size <= 0
      ) return false;
    }
    accessSync(join(canonical, "bin", "mainframe"), constants.X_OK);
    accessSync(join(canonical, "control_plane", "mainframe-control-plane"), constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/** Select the root for safe broker calls without bypassing explicit choices. */
function configuredBrokerRoot(): string {
  if (mainframeRootSetByConfig) return config.mainframeRoot;

  const environmentRoot = process.env.MAINFRAME_ROOT;
  if (environmentRoot !== undefined) return environmentRoot;

  // Automatic configuration remains live so a managed install activated
  // after module import still precedes a stale legacy ~/.mainframe tree.
  const detectedRoot = detectMainframeRoot();
  if (detectedRoot) {
    config.mainframeRoot = detectedRoot;
    return detectedRoot;
  }
  return config.mainframeRoot;
}

/**
 * Verify MAINFRAME is properly installed
 */
export function verifyInstallation(): {
  installed: boolean;
  root: string | null;
  version: string | null;
  error?: string;
} {
  const root = detectMainframeRoot();

  if (!root) {
    return {
      installed: false,
      root: null,
      version: null,
      error: "MAINFRAME not found. Install to ~/.mainframe or set MAINFRAME_ROOT",
    };
  }

  // Try to get version
  try {
    const result = execBash(`echo "$MAINFRAME_VERSION"`, { env: { MAINFRAME_ROOT: root } });
    const version = result.stdout.trim() || null;
    return { installed: true, root, version };
  } catch {
    return { installed: true, root, version: null };
  }
}

// =============================================================================
// Execution Engine
// =============================================================================

interface ExecOptions {
  env?: Record<string, string>;
  timeout?: number;
  cwd?: string;
}

interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

const FUNCTION_NAME_PATTERN = /^[A-Za-z_][A-Za-z0-9_:]*$/;
const BROKER_FUNCTION_NAME_PATTERN = /^[a-z_][a-z0-9_]*$/;
const CANONICAL_ID_PATTERN = /^mf:[a-z][a-z0-9-]*:[A-Za-z0-9_-]+:[a-z_][a-z0-9_]*$/;
const BROKER_STATUSES = new Set([
  "success",
  "function_error",
  "timeout",
  "output_limit",
  "audit_error",
  "invalid_input",
  "invalid_id",
  "invalid_manifest",
  "unknown_id",
  "invalid_contract",
  "unreviewed_contract",
  "owner_mismatch",
  "unsupported_platform",
  "invalid_owner",
  "broker_error",
]);
const BROKER_FIXED_EXIT_CODES: Readonly<Record<string, number>> = {
  success: 0,
  timeout: 124,
  output_limit: 74,
  audit_error: 74,
  invalid_input: 65,
  invalid_id: 126,
  invalid_manifest: 126,
  unknown_id: 126,
  invalid_contract: 126,
  unreviewed_contract: 126,
  owner_mismatch: 126,
  unsupported_platform: 126,
  invalid_owner: 126,
  broker_error: 70,
};
const BROKER_AUDIT_ID_PATTERN = /^inv-[A-Za-z0-9._:-]{1,120}$/;
const MANIFEST_SIZE_LIMIT = 16 * 1024 * 1024;
const BROKER_INPUT_LIMIT = 32 * 1024;
const BROKER_ENVELOPE_LIMIT = 3 * 1024 * 1024;
const BROKER_MAX_TIMEOUT_MS = 30000;
const BROKER_OUTER_TIMEOUT_MS = 35000;
const BROKER_MAX_OUTPUT_LIMIT = 1024 * 1024;
const BROKER_ENVELOPE_KEYS = [
  "audit_id",
  "canonical_id",
  "duration_ms",
  "error",
  "exit_code",
  "name",
  "ok",
  "output_exceeded",
  "owner",
  "schema_version",
  "status",
  "stderr_b64",
  "stdout_b64",
  "timed_out",
] as const;
const CONTROL_PLANE_OUTER_KEYS = ["command", "ok", "result"] as const;
const CONTROL_PLANE_RESULT_KEYS = [
  "broker_envelope",
  "broker_receipt",
  "call_id",
  "client_correlation_id",
  "decision_id",
  "evidence_id",
  "input_digest",
  "outcome",
  "result_available",
  "run_id",
  "schema_version",
  "status",
] as const;
const BROKER_RECEIPT_KEYS = [
  "audit_id",
  "canonical_id",
  "duration_ms",
  "error_bytes",
  "error_sha256",
  "exit_code",
  "name",
  "ok",
  "output_exceeded",
  "owner",
  "schema_version",
  "status",
  "stderr_bytes",
  "stderr_sha256",
  "stdout_bytes",
  "stdout_sha256",
  "timed_out",
] as const;
const DURABLE_CLOSURE_FILES = [
  "bin/mainframe",
  "lib/common.sh",
  "lib/durable_invoke.sh",
  "control_plane/mainframe-control-plane",
  "control_plane/mainframe_control_plane/__init__.py",
  "control_plane/mainframe_control_plane/cli.py",
  "control_plane/mainframe_control_plane/coding.py",
  "control_plane/mainframe_control_plane/contracts.py",
  "control_plane/mainframe_control_plane/durability.py",
  "control_plane/mainframe_control_plane/errors.py",
  "control_plane/mainframe_control_plane/executor.py",
  "control_plane/mainframe_control_plane/kernel.py",
  "control_plane/mainframe_control_plane/memory.py",
  "control_plane/mainframe_control_plane/memory_executor.py",
  "control_plane/mainframe_control_plane/memory_transient.py",
  "control_plane/mainframe_control_plane/memory_worker.py",
  "control_plane/mainframe_control_plane/transient.py",
  "control_plane/mainframe_control_plane/worker.py",
] as const;
const DURABLE_ID_PATTERNS = {
  run_id: /^run-[0-9a-f]{32}$/,
  call_id: /^call-[0-9a-f]{32}$/,
  decision_id: /^decision-[0-9a-f]{32}$/,
  evidence_id: /^evidence-[0-9a-f]{32}$/,
} as const;
const CLIENT_CORRELATION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const DIGEST_PATTERN = /^[0-9a-f]{64}$/;

/*
 * spawnSync cannot create and later kill a dedicated process group itself.
 * This fixed Node runner starts the exact broker executable detached, bounds
 * combined output, and always signals the whole group on timeout, overflow,
 * parent termination, or runner error. It emits only the broker's own bytes.
 */
const BROKER_RUNNER_SOURCE = String.raw`
const { spawn } = require("node:child_process");

const config = JSON.parse(Buffer.from(process.argv[1], "base64").toString("utf8"));
const inputChunks = [];
let inputBytes = 0;
let child = null;
let finished = false;
const TERM_GRACE_MS = 500;
const KILL_REAP_MS = 500;

function signalGroup(signal) {
  if (!child || !child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch {
    try { child.kill(signal); } catch {}
  }
}

function emitFailure(message, code) {
  process.stderr.write(message + "\n", () => process.exit(code));
}

function fail(message, code) {
  if (finished) return;
  finished = true;
  if (!child || !child.pid) {
    emitFailure(message, code);
    return;
  }

  // Give lib/invoke.sh's TERM trap time to terminate and reap its nested
  // process group before enforcing the outer hard stop.
  signalGroup("SIGTERM");
  setTimeout(() => {
    signalGroup("SIGKILL");
    if (child.exitCode !== null || child.signalCode !== null) {
      emitFailure(message, code);
      return;
    }
    let emitted = false;
    const emitOnce = () => {
      if (emitted) return;
      emitted = true;
      emitFailure(message, code);
    };
    child.once("close", emitOnce);
    setTimeout(emitOnce, KILL_REAP_MS);
  }, TERM_GRACE_MS);
}

for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
  process.on(signal, () => fail("broker runner interrupted", 70));
}

process.stdin.on("data", (chunk) => {
  inputBytes += chunk.length;
  if (inputBytes > config.inputLimit) {
    fail("broker runner input limit exceeded", 65);
    return;
  }
  inputChunks.push(chunk);
});

process.stdin.on("end", () => {
  if (finished) return;
  const childEnvironment = { ...process.env };
  child = spawn(config.executable, config.args, {
    detached: true,
    env: childEnvironment,
    stdio: ["pipe", "pipe", "pipe"],
  });

  const stdoutChunks = [];
  const stderrChunks = [];
  let outputBytes = 0;
  const timer = setTimeout(
    () => fail("broker runner timeout exceeded", 124),
    config.timeout,
  );

  function capture(target, chunk) {
    if (finished) return;
    outputBytes += chunk.length;
    if (outputBytes > config.outputLimit) {
      clearTimeout(timer);
      fail("broker runner output limit exceeded", 74);
      return;
    }
    target.push(chunk);
  }

  child.stdout.on("data", (chunk) => capture(stdoutChunks, chunk));
  child.stderr.on("data", (chunk) => capture(stderrChunks, chunk));
  child.on("error", (error) => {
    clearTimeout(timer);
    fail("broker runner launch failed: " + error.message, 70);
  });
  child.on("close", (code, signal) => {
    clearTimeout(timer);
    if (finished) return;
    if (signal || !Number.isInteger(code) || code < 0 || code > 255) {
      fail("broker runner observed an invalid child exit", 70);
      return;
    }
    finished = true;
    process.stdout.write(Buffer.concat(stdoutChunks));
    process.stderr.write(Buffer.concat(stderrChunks));
    process.exitCode = code;
  });
  child.stdin.on("error", (error) => {
    clearTimeout(timer);
    fail("broker runner stdin failed: " + error.message, 70);
  });
  child.stdin.end(Buffer.concat(inputChunks));
});

process.stdin.resume();
`;

interface BrokerPropertyContract {
  type: "string" | "array";
  items?: { type: "string" };
  default?: string | string[];
  enum?: string[];
}

interface BrokerCallArgument {
  field: string;
  mode: "scalar" | "spread";
}

interface ReviewedBrokerContract {
  canonicalId: string;
  name: string;
  owner: string;
  resultKind: "stdout" | "exit" | "none";
  required: Set<string>;
  properties: Record<string, BrokerPropertyContract>;
  callArguments: BrokerCallArgument[];
  timeoutMs: number;
  outputLimit: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function canonicalMainframeRoot(root: string): string {
  try {
    const canonical = realpathSync(root);
    if (!durableRootIsUsable(canonical)) throw new Error("not a durable installation");
    return canonical;
  } catch {
    throw new Error("MAINFRAME root is missing or invalid");
  }
}

function loadReviewedContract(
  root: string,
  canonicalId: string,
  expectedName?: string,
): ReviewedBrokerContract {
  if (!CANONICAL_ID_PATTERN.test(canonicalId)) {
    throw new Error(`Invalid MAINFRAME canonical ID: ${canonicalId}`);
  }

  const manifestPath = join(root, "MANIFEST.json");
  let manifestValue: unknown;
  try {
    const metadata = lstatSync(manifestPath);
    if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > MANIFEST_SIZE_LIMIT) {
      throw new Error("unsafe manifest");
    }
    manifestValue = JSON.parse(readFileSync(manifestPath, "utf8")) as unknown;
  } catch {
    throw new Error("MAINFRAME canonical manifest is missing, oversized, or malformed");
  }

  if (
    !isRecord(manifestValue) ||
    manifestValue.manifest_version !== 1 ||
    !isRecord(manifestValue.exports) ||
    !isRecord(manifestValue.name_index)
  ) {
    throw new Error("MAINFRAME canonical manifest is malformed");
  }

  const value = manifestValue.exports[canonicalId];
  if (!isRecord(value)) {
    throw new Error(`Canonical ID is not registered: ${canonicalId}`);
  }
  const name = value.name;
  const owner = value.owner;
  if (
    typeof name !== "string" ||
    !BROKER_FUNCTION_NAME_PATTERN.test(name) ||
    typeof owner !== "string" ||
    !/^[A-Za-z0-9_-]+$/.test(owner) ||
    (expectedName !== undefined && name !== expectedName) ||
    manifestValue.name_index[name] !== canonicalId
  ) {
    throw new Error("Canonical manifest name/owner parity check failed");
  }

  if (
    value.contract_status !== "reviewed" ||
    !Array.isArray(value.profiles) ||
    !value.profiles.includes("stable-core") ||
    !Array.isArray(value.effects) ||
    value.effects.length !== 1 ||
    !value.effects.every((effect) => effect === "pure" || effect === "read") ||
    !Array.isArray(value.capabilities) ||
    value.capabilities.length !== 0
  ) {
    throw new Error(`MAINFRAME function is not reviewed for stable-core: ${name}`);
  }

  const resultContract = value.result;
  if (
    !isRecord(resultContract) ||
    Object.keys(resultContract).length !== 1 ||
    (resultContract.kind !== "stdout" &&
      resultContract.kind !== "exit" &&
      resultContract.kind !== "none")
  ) {
    throw new Error(`Reviewed contract has an invalid result contract: ${canonicalId}`);
  }

  const schema = value.input_schema;
  if (
    !isRecord(schema) ||
    Object.keys(schema).sort().join("\0") !==
      ["additionalProperties", "properties", "required", "type"].join("\0") ||
    schema.type !== "object" ||
    schema.additionalProperties !== false ||
    !isRecord(schema.properties) ||
    !Array.isArray(schema.required) ||
    !schema.required.every((field) => typeof field === "string") ||
    new Set(schema.required).size !== schema.required.length
  ) {
    throw new Error(`Reviewed contract has an invalid input schema: ${canonicalId}`);
  }

  const required = new Set(schema.required as string[]);
  const properties: Record<string, BrokerPropertyContract> = {};
  for (const [field, propertyValue] of Object.entries(schema.properties)) {
    if (!BROKER_FUNCTION_NAME_PATTERN.test(field) || !isRecord(propertyValue)) {
      throw new Error(`Reviewed contract has an invalid property: ${canonicalId}`);
    }
    if (propertyValue.type === "string") {
      const propertyKeys = Object.keys(propertyValue);
      if (
        propertyKeys.some((key) => key !== "type" && key !== "default" && key !== "enum") ||
        ("default" in propertyValue && typeof propertyValue.default !== "string") ||
        (typeof propertyValue.default === "string" && propertyValue.default.includes("\0")) ||
        ("enum" in propertyValue &&
          (!Array.isArray(propertyValue.enum) ||
            !propertyValue.enum.every(
              (entry) => typeof entry === "string" && !entry.includes("\0"),
            ))) ||
        (!required.has(field) && typeof propertyValue.default !== "string")
      ) {
        throw new Error(`Reviewed contract has an invalid string property: ${canonicalId}`);
      }
      properties[field] = {
        type: "string",
        ...(typeof propertyValue.default === "string" && { default: propertyValue.default }),
        ...(Array.isArray(propertyValue.enum) && { enum: propertyValue.enum as string[] }),
      };
    } else if (
      propertyValue.type === "array" &&
      Object.keys(propertyValue).every(
        (key) => key === "type" || key === "items" || key === "default",
      ) &&
      isRecord(propertyValue.items) &&
      Object.keys(propertyValue.items).length === 1 &&
      propertyValue.items.type === "string" &&
      (!("default" in propertyValue) ||
        (Array.isArray(propertyValue.default) &&
          propertyValue.default.every(
            (entry) => typeof entry === "string" && !entry.includes("\0"),
          ))) &&
      (required.has(field) ||
        (Array.isArray(propertyValue.default) && propertyValue.default.length === 0))
    ) {
      properties[field] = {
        type: "array",
        items: { type: "string" },
        ...(Array.isArray(propertyValue.default) && {
          default: propertyValue.default as string[],
        }),
      };
    } else {
      throw new Error(`Reviewed contract has an unsupported property: ${canonicalId}`);
    }
  }

  if ([...required].some((field) => !(field in properties))) {
    throw new Error(`Reviewed contract requires an unknown property: ${canonicalId}`);
  }

  const callShape = value.call_shape;
  if (
    !isRecord(callShape) ||
    Object.keys(callShape).sort().join("\0") !== "arguments\0kind" ||
    callShape.kind !== "argv" ||
    !Array.isArray(callShape.arguments)
  ) {
    throw new Error(`Reviewed contract has an invalid call shape: ${canonicalId}`);
  }
  const callArguments: BrokerCallArgument[] = [];
  for (const [index, argumentValue] of callShape.arguments.entries()) {
    if (
      !isRecord(argumentValue) ||
      Object.keys(argumentValue).sort().join("\0") !== "field\0mode"
    ) {
      throw new Error(`Reviewed contract has an invalid call argument: ${canonicalId}`);
    }
    const field = argumentValue.field;
    const mode = argumentValue.mode;
    const property = typeof field === "string" ? properties[field] : undefined;
    if (
      typeof field !== "string" ||
      (mode !== "scalar" && mode !== "spread") ||
      property === undefined ||
      (mode === "scalar" && property.type !== "string") ||
      (mode === "spread" && property.type !== "array") ||
      (mode === "spread" && index !== callShape.arguments.length - 1)
    ) {
      throw new Error(`Reviewed contract call shape is not positional: ${canonicalId}`);
    }
    callArguments.push({ field, mode });
  }
  const shapeFields = callArguments.map(({ field }) => field);
  if (
    new Set(shapeFields).size !== shapeFields.length ||
    shapeFields.slice().sort().join("\0") !== Object.keys(properties).sort().join("\0")
  ) {
    throw new Error(`Reviewed contract call shape is not closed: ${canonicalId}`);
  }

  const timeoutMs = value.timeout_ms;
  const outputLimit = value.output_limit;
  if (
    typeof timeoutMs !== "number" ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs < 1 ||
    timeoutMs > BROKER_MAX_TIMEOUT_MS ||
    typeof outputLimit !== "number" ||
    !Number.isInteger(outputLimit) ||
    outputLimit < 1 ||
    outputLimit > BROKER_MAX_OUTPUT_LIMIT
  ) {
    throw new Error(`Reviewed contract has invalid execution bounds: ${canonicalId}`);
  }

  return {
    canonicalId,
    name,
    owner,
    resultKind: resultContract.kind,
    required,
    properties,
    callArguments,
    timeoutMs,
    outputLimit,
  };
}

function resolveFunctionContract(root: string, functionName: string): ReviewedBrokerContract {
  const manifestPath = join(root, "MANIFEST.json");
  let manifestValue: unknown;
  try {
    const metadata = lstatSync(manifestPath);
    if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > MANIFEST_SIZE_LIMIT) {
      throw new Error("unsafe manifest");
    }
    manifestValue = JSON.parse(readFileSync(manifestPath, "utf8")) as unknown;
  } catch {
    throw new Error("MAINFRAME canonical manifest is missing, oversized, or malformed");
  }
  if (!isRecord(manifestValue) || !isRecord(manifestValue.name_index)) {
    throw new Error("MAINFRAME canonical manifest is malformed");
  }
  const canonicalId = manifestValue.name_index[functionName];
  if (typeof canonicalId !== "string") {
    throw new Error(`MAINFRAME function is not broker-invocable: ${functionName}`);
  }
  return loadReviewedContract(root, canonicalId, functionName);
}

function positionalInput(
  contract: ReviewedBrokerContract,
  args: (string | number | boolean)[],
): Record<string, string | string[]> {
  const input: Record<string, string | string[]> = {};
  let position = 0;
  for (const argument of contract.callArguments) {
    const property = contract.properties[argument.field];
    if (argument.mode === "spread") {
      input[argument.field] = args.slice(position).map(String);
      position = args.length;
    } else if (position < args.length) {
      input[argument.field] = String(args[position]);
      position += 1;
    } else if (contract.required.has(argument.field) && property.default === undefined) {
      throw new Error(`Missing required argument '${argument.field}' for ${contract.name}`);
    }
  }
  if (position !== args.length) {
    throw new Error(`Too many positional arguments for ${contract.name}`);
  }
  return input;
}

function validateCanonicalInput(
  contract: ReviewedBrokerContract,
  input: Record<string, unknown>,
): Record<string, string | string[]> {
  if (!isRecord(input)) {
    throw new Error("Canonical invocation input must be an object");
  }
  const normalized: Record<string, string | string[]> = {};
  for (const [field, value] of Object.entries(input)) {
    const property = contract.properties[field];
    if (!property) throw new Error(`Canonical input contains undeclared field '${field}'`);
    if (property.type === "string") {
      if (
        typeof value !== "string" ||
        value.includes("\0") ||
        (property.enum && !property.enum.includes(value))
      ) {
        throw new Error(`Canonical input field '${field}' must be a permitted string`);
      }
      normalized[field] = value;
    } else {
      if (!Array.isArray(value) || !value.every((entry) => typeof entry === "string" && !entry.includes("\0"))) {
        throw new Error(`Canonical input field '${field}' must be an array of strings`);
      }
      normalized[field] = value.slice();
    }
  }
  for (const field of contract.required) {
    if (!(field in normalized)) throw new Error(`Canonical input is missing required field '${field}'`);
  }
  for (const [field, property] of Object.entries(contract.properties)) {
    if (!(field in normalized) && property.default !== undefined) {
      normalized[field] = Array.isArray(property.default)
        ? property.default.slice()
        : property.default;
    }
  }
  return normalized;
}

function decodeCanonicalBase64(value: string, field: string): Buffer {
  if (
    value.length % 4 !== 0 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)
  ) {
    throw new Error(`Broker envelope contains invalid ${field}`);
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.toString("base64") !== value) {
    throw new Error(`Broker envelope contains non-canonical ${field}`);
  }
  return decoded;
}

function assertNoDuplicateJsonKeys(raw: string): void {
  let index = 0;
  const skip = () => { while (/\s/.test(raw[index] ?? "")) index += 1; };
  const parseString = (): string => {
    const start = index;
    if (raw[index] !== '"') throw new Error("expected JSON string");
    index += 1;
    while (index < raw.length) {
      const char = raw[index++];
      if (char === '"') return JSON.parse(raw.slice(start, index)) as string;
      if (char === "\\") {
        const escaped = raw[index++];
        if (escaped === "u") index += 4;
      }
    }
    throw new Error("unterminated JSON string");
  };
  const parseValue = (): void => {
    skip();
    const char = raw[index];
    if (char === "{") {
      index += 1;
      skip();
      const keys = new Set<string>();
      if (raw[index] === "}") { index += 1; return; }
      while (true) {
        skip();
        const key = parseString();
        if (keys.has(key)) throw new Error(`duplicate JSON object key: ${key}`);
        keys.add(key);
        skip();
        if (raw[index++] !== ":") throw new Error("missing JSON object colon");
        parseValue();
        skip();
        const separator = raw[index++];
        if (separator === "}") return;
        if (separator !== ",") throw new Error("invalid JSON object separator");
      }
    }
    if (char === "[") {
      index += 1;
      skip();
      if (raw[index] === "]") { index += 1; return; }
      while (true) {
        parseValue();
        skip();
        const separator = raw[index++];
        if (separator === "]") return;
        if (separator !== ",") throw new Error("invalid JSON array separator");
      }
    }
    if (char === '"') { parseString(); return; }
    const match = /^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(raw.slice(index));
    if (!match) throw new Error("invalid JSON scalar");
    index += match[0].length;
  };
  parseValue();
  skip();
  if (index !== raw.length) throw new Error("trailing JSON content");
}

function parseUnambiguousJson(raw: string): unknown {
  assertNoDuplicateJsonKeys(raw);
  return JSON.parse(raw) as unknown;
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  const rendered = JSON.stringify(value);
  if (rendered === undefined) throw new Error("Canonical input contains an unsupported value");
  return rendered;
}

function parseBrokerEnvelope(
  rawOutput: Buffer,
  processStderr: Buffer,
  processExitCode: number | null,
  contract: ReviewedBrokerContract,
): Omit<BrokerInvocationResult, "controlPlane"> & { envelope: BrokerEnvelopeV1 } {
  if (rawOutput.byteLength === 0 || rawOutput.byteLength > BROKER_ENVELOPE_LIMIT) {
    throw new Error("Broker response is empty or exceeds the envelope limit");
  }
  if (processStderr.byteLength !== 0) {
    throw new Error("Broker wrote outside the versioned response envelope");
  }

  const raw = new TextDecoder("utf-8", { fatal: true }).decode(rawOutput).trim();
  let parsed: unknown;
  try {
    parsed = parseUnambiguousJson(raw);
  } catch {
    throw new Error("Broker response is not valid JSON");
  }
  if (!isRecord(parsed)) throw new Error("Broker response is not a JSON object");
  if (Object.keys(parsed).sort().join("\0") !== BROKER_ENVELOPE_KEYS.join("\0")) {
    throw new Error("Broker response does not match broker-json-v1");
  }

  const envelope = parsed as unknown as BrokerEnvelopeV1;
  if (
    envelope.schema_version !== 1 ||
    typeof envelope.ok !== "boolean" ||
    typeof envelope.status !== "string" ||
    !BROKER_STATUSES.has(envelope.status) ||
    envelope.canonical_id !== contract.canonicalId ||
    envelope.name !== contract.name ||
    envelope.owner !== contract.owner ||
    typeof envelope.exit_code !== "number" ||
    !Number.isInteger(envelope.exit_code) ||
    envelope.exit_code < 0 ||
    envelope.exit_code > 255 ||
    typeof envelope.timed_out !== "boolean" ||
    typeof envelope.output_exceeded !== "boolean" ||
    typeof envelope.duration_ms !== "number" ||
    !Number.isInteger(envelope.duration_ms) ||
    envelope.duration_ms < 0 ||
    typeof envelope.audit_id !== "string" ||
    !BROKER_AUDIT_ID_PATTERN.test(envelope.audit_id) ||
    typeof envelope.stdout_b64 !== "string" ||
    typeof envelope.stderr_b64 !== "string" ||
    (envelope.error !== null && typeof envelope.error !== "string") ||
    (envelope.timed_out && envelope.output_exceeded) ||
    (envelope.ok &&
      (envelope.status !== "success" ||
        envelope.exit_code !== 0 ||
        envelope.timed_out ||
        envelope.output_exceeded ||
        envelope.error !== null)) ||
    (!envelope.ok && (envelope.status === "success" || envelope.exit_code === 0)) ||
    envelope.timed_out !== (envelope.status === "timeout") ||
    envelope.output_exceeded !== (envelope.status === "output_limit") ||
    (envelope.status === "function_error" && envelope.exit_code === 0) ||
    (envelope.status !== "function_error" &&
      BROKER_FIXED_EXIT_CODES[envelope.status] !== envelope.exit_code) ||
    processExitCode === null ||
    processExitCode !== envelope.exit_code
  ) {
    throw new Error("Broker response failed identity or semantic validation");
  }

  const stdoutBytes = decodeCanonicalBase64(envelope.stdout_b64, "stdout_b64");
  const stderrBytes = decodeCanonicalBase64(envelope.stderr_b64, "stderr_b64");
  if (stdoutBytes.byteLength + stderrBytes.byteLength > contract.outputLimit) {
    throw new Error("Broker response exceeds the reviewed output bound");
  }
  if (contract.resultKind !== "stdout" && stdoutBytes.byteLength !== 0) {
    throw new Error("Broker output contradicts the reviewed result contract");
  }
  const decoder = new TextDecoder("utf-8", { fatal: true });
  return {
    envelope,
    resultKind: contract.resultKind,
    stdout: decoder.decode(stdoutBytes),
    stderr: decoder.decode(stderrBytes),
    raw,
  };
}

function validateDurableId(value: unknown, field: keyof typeof DURABLE_ID_PATTERNS): string {
  if (typeof value !== "string" || !DURABLE_ID_PATTERNS[field].test(value)) {
    throw new Error(`Control-plane response contains an invalid ${field}`);
  }
  return value;
}

function validateBrokerReceipt(
  value: unknown,
  envelope: BrokerEnvelopeV1 | null,
  contract: ReviewedBrokerContract,
): BrokerReceiptV1 | null {
  if (value === null) return null;
  if (!isRecord(value) || Object.keys(value).sort().join("\0") !== BROKER_RECEIPT_KEYS.join("\0")) {
    throw new Error("Control-plane broker receipt fields are not exact");
  }
  const receipt = value as unknown as BrokerReceiptV1;
  for (const field of ["schema_version", "exit_code", "duration_ms", "stdout_bytes", "stderr_bytes", "error_bytes"] as const) {
    if (!Number.isInteger(receipt[field]) || receipt[field] < 0) {
      throw new Error("Control-plane broker receipt has invalid numeric fields");
    }
  }
  for (const field of ["ok", "timed_out", "output_exceeded"] as const) {
    if (typeof receipt[field] !== "boolean") {
      throw new Error("Control-plane broker receipt has invalid boolean fields");
    }
  }
  if (
    receipt.schema_version !== 1 ||
    receipt.canonical_id !== contract.canonicalId ||
    receipt.name !== contract.name ||
    receipt.owner !== contract.owner ||
    typeof receipt.status !== "string" ||
    typeof receipt.audit_id !== "string"
  ) throw new Error("Control-plane broker receipt identity is invalid");
  const expectedExit = BROKER_FIXED_EXIT_CODES[receipt.status];
  if (
    !BROKER_STATUSES.has(receipt.status) ||
    !BROKER_AUDIT_ID_PATTERN.test(receipt.audit_id) ||
    receipt.exit_code > 255 ||
    receipt.duration_ms > contract.timeoutMs + 5_000 ||
    receipt.stdout_bytes + receipt.stderr_bytes > contract.outputLimit ||
    receipt.error_bytes > 4_096 ||
    receipt.ok !== (receipt.status === "success") ||
    (receipt.ok ? receipt.exit_code !== 0 : receipt.exit_code === 0) ||
    receipt.timed_out !== (receipt.status === "timeout") ||
    receipt.output_exceeded !== (receipt.status === "output_limit") ||
    (receipt.status === "function_error"
      ? receipt.exit_code === 0
      : (expectedExit === undefined || receipt.exit_code !== expectedExit))
  ) throw new Error("Control-plane broker receipt semantics are invalid");
  for (const field of ["stdout_sha256", "stderr_sha256", "error_sha256"] as const) {
    if (typeof receipt[field] !== "string" || !DIGEST_PATTERN.test(receipt[field])) {
      throw new Error("Control-plane broker receipt digest is invalid");
    }
  }
  if (envelope === null) return receipt;
  for (const field of [
    "schema_version", "ok", "status", "canonical_id", "name", "owner", "exit_code",
    "timed_out", "output_exceeded", "duration_ms", "audit_id",
  ] as const) {
    if (receipt[field] !== envelope[field]) {
      throw new Error("Control-plane receipt does not bind the broker envelope");
    }
  }
  const payloads = {
    stdout: decodeCanonicalBase64(envelope.stdout_b64, "stdout_b64"),
    stderr: decodeCanonicalBase64(envelope.stderr_b64, "stderr_b64"),
    error: Buffer.from(envelope.error ?? "", "utf8"),
  };
  for (const [prefix, payload] of Object.entries(payloads) as ["stdout" | "stderr" | "error", Buffer][]) {
    if (
      receipt[`${prefix}_bytes`] !== payload.byteLength ||
      receipt[`${prefix}_sha256`] !== createHash("sha256").update(payload).digest("hex")
    ) throw new Error("Control-plane receipt payload digest is invalid");
  }
  return receipt;
}

function parseControlPlaneResponse(
  rawOutput: Buffer,
  processStderr: Buffer,
  processExitCode: number | null,
  contract: ReviewedBrokerContract,
  correlationId: string,
  inputDigest: string,
): BrokerInvocationResult {
  if (rawOutput.byteLength === 0 || rawOutput.byteLength > BROKER_ENVELOPE_LIMIT || rawOutput.at(-1) !== 0x0a) {
    throw new Error("Control-plane response is empty, unterminated, or oversized");
  }
  if (processStderr.byteLength !== 0) throw new Error("Control-plane wrote outside its structured response");
  const raw = new TextDecoder("utf-8", { fatal: true }).decode(rawOutput.subarray(0, -1));
  let parsed: unknown;
  try { parsed = parseUnambiguousJson(raw); } catch { throw new Error("Control-plane response is not unambiguous JSON"); }
  if (!isRecord(parsed)) throw new Error("Control-plane response is not an object");
  if (processExitCode !== 0) {
    if (
      Object.keys(parsed).sort().join("\0") !== ["command", "error", "ok"].join("\0") ||
      parsed.ok !== false || parsed.command !== "canonical-invoke" || !isRecord(parsed.error) ||
      Object.keys(parsed.error).sort().join("\0") !== ["code", "message"].join("\0") ||
      typeof parsed.error.code !== "string" || typeof parsed.error.message !== "string"
    ) throw new Error("Control-plane error response is invalid");
    throw new Error(`${parsed.error.code}: ${parsed.error.message}`);
  }
  if (
    Object.keys(parsed).sort().join("\0") !== CONTROL_PLANE_OUTER_KEYS.join("\0") ||
    parsed.ok !== true || parsed.command !== "canonical-invoke" || !isRecord(parsed.result)
  ) throw new Error("Control-plane success response fields are not exact");
  const result = parsed.result;
  if (Object.keys(result).sort().join("\0") !== CONTROL_PLANE_RESULT_KEYS.join("\0")) {
    throw new Error("Control-plane durable result fields are not exact");
  }
  if (result.schema_version !== 1 || (result.status !== "in_progress" && result.status !== "completed")) {
    throw new Error("Control-plane schema or durable status is invalid");
  }
  if (
    typeof result.client_correlation_id !== "string" ||
    !CLIENT_CORRELATION_PATTERN.test(result.client_correlation_id) ||
    result.client_correlation_id !== correlationId
  ) throw new Error("Control-plane client correlation binding is invalid");
  const runId = validateDurableId(result.run_id, "run_id");
  const callId = validateDurableId(result.call_id, "call_id");
  const decisionId = validateDurableId(result.decision_id, "decision_id");
  if (result.input_digest !== inputDigest || !DIGEST_PATTERN.test(inputDigest)) {
    throw new Error("Control-plane input digest binding is invalid");
  }
  if (typeof result.result_available !== "boolean") throw new Error("Control-plane result availability is invalid");
  let evidenceId: string | null = null;
  if (result.status === "in_progress") {
    if (
      result.evidence_id !== null || result.outcome !== null || result.result_available !== false ||
      result.broker_receipt !== null || result.broker_envelope !== null
    ) throw new Error("Control-plane in-progress result is contradictory");
  } else {
    evidenceId = validateDurableId(result.evidence_id, "evidence_id");
    if (!["succeeded", "failed", "timed_out", "interrupted"].includes(String(result.outcome))) {
      throw new Error("Control-plane terminal outcome is invalid");
    }
    if (result.result_available !== (result.broker_envelope !== null)) {
      throw new Error("Control-plane result availability contradicts its envelope");
    }
  }
  let decoded: ReturnType<typeof parseBrokerEnvelope> | null = null;
  let envelope: BrokerEnvelopeV1 | null = null;
  if (result.broker_envelope !== null) {
    if (!isRecord(result.broker_envelope)) throw new Error("Control-plane broker envelope is invalid");
    const candidate = result.broker_envelope as unknown as BrokerEnvelopeV1;
    const candidateCode = typeof candidate.exit_code === "number" ? candidate.exit_code : -1;
    decoded = parseBrokerEnvelope(
      Buffer.from(JSON.stringify(candidate), "utf8"), Buffer.alloc(0), candidateCode, contract,
    );
    envelope = decoded.envelope;
    const expectedOutcome = decoded.envelope.ok ? "succeeded" : (decoded.envelope.timed_out ? "timed_out" : "failed");
    if (result.outcome !== expectedOutcome) throw new Error("Control-plane outcome contradicts the broker envelope");
  }
  const receipt = validateBrokerReceipt(result.broker_receipt, envelope, contract);
  if (envelope !== null && receipt === null) throw new Error("Control-plane available result lacks its durable receipt");
  if (receipt !== null) {
    const receiptOutcome = receipt.ok ? "succeeded" : (receipt.timed_out ? "timed_out" : "failed");
    if (result.outcome !== receiptOutcome) throw new Error("Control-plane outcome contradicts its durable receipt");
  }
  const controlPlane: ControlPlaneInvocationV1 = {
    schemaVersion: 1,
    status: result.status,
    clientCorrelationId: result.client_correlation_id,
    runId,
    callId,
    decisionId,
    evidenceId,
    inputDigest,
    outcome: result.outcome as ControlPlaneInvocationV1["outcome"],
    resultAvailable: result.result_available,
    brokerReceipt: receipt,
  };
  return {
    controlPlane,
    envelope,
    resultKind: contract.resultKind,
    stdout: decoded?.stdout ?? "",
    stderr: decoded?.stderr ?? "",
    raw: decoded?.raw ?? "",
  };
}

function runBoundedBrokerProcess(
  executable: string,
  args: string[],
  request: Buffer,
  environment: NodeJS.ProcessEnv,
  timeout: number,
  cwd?: string,
): SpawnSyncReturns<Buffer> {
  const runnerConfig = Buffer.from(
    JSON.stringify({
      executable,
      args,
      timeout,
      inputLimit: BROKER_INPUT_LIMIT,
      outputLimit: BROKER_ENVELOPE_LIMIT,
    }),
    "utf8",
  ).toString("base64");
  return spawnSync(
    process.execPath,
    ["--input-type=commonjs", "-e", BROKER_RUNNER_SOURCE, runnerConfig],
    {
      input: request,
      env: environment,
      timeout: timeout + 2000,
      killSignal: "SIGTERM",
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      maxBuffer: BROKER_ENVELOPE_LIMIT + 65536,
    },
  );
}

function invokeReviewedContract(
  root: string,
  contract: ReviewedBrokerContract,
  input: Record<string, unknown>,
  options: BrokerInvokeOptions = {},
): BrokerInvocationResult {
  const normalizedInput = validateCanonicalInput(contract, input);
  const request = Buffer.from(JSON.stringify(normalizedInput), "utf8");
  const inputDigest = createHash("sha256").update(canonicalJson(normalizedInput), "utf8").digest("hex");
  const correlationId = `client-nodejs-${randomUUID().replaceAll("-", "")}`;
  if (request.byteLength > BROKER_INPUT_LIMIT) {
    throw new Error("Canonical invocation input exceeds 32768 bytes");
  }

  const executable = join(root, "bin", "mainframe");
  try {
    const metadata = lstatSync(executable);
    if (!metadata.isFile() || metadata.isSymbolicLink()) throw new Error("unsafe executable");
    accessSync(executable, constants.X_OK);
  } catch {
    throw new Error("MAINFRAME canonical broker is missing or unsafe");
  }

  const timeout = options.timeout ?? Math.min(config.timeout, contract.timeoutMs + 5000);
  if (!Number.isInteger(timeout) || timeout < 1 || timeout > BROKER_OUTER_TIMEOUT_MS) {
    throw new Error("Broker timeout must be an integer from 1 through 35000 milliseconds");
  }
  const environment = protectedExecutionEnvironment(options.env);
  environment.MAINFRAME_ROOT = root;
  const brokerArgs = [
    "invoke",
    contract.canonicalId,
    "--input-json",
    "-",
    "--profile",
    "stable-core",
    "--format",
    "control-plane-json-v1",
    "--caller",
    "nodejs",
    "--client-correlation-id",
    correlationId,
  ];
  const result = runBoundedBrokerProcess(
    executable,
    brokerArgs,
    request,
    environment,
    timeout,
    options.cwd,
  );
  if (result.error) {
    throw new Error(`Broker process failed: ${result.error.message}`);
  }
  return parseControlPlaneResponse(
    result.stdout ?? Buffer.alloc(0),
    result.stderr ?? Buffer.alloc(0),
    result.status,
    contract,
    correlationId,
    inputDigest,
  );
}

/**
 * Invoke one reviewed stable-core export by canonical ID.
 *
 * This is the safe, structured adapter. It does not evaluate shell text and it
 * accepts only fields declared by the reviewed manifest contract.
 */
export function invokeCanonical(
  canonicalId: string,
  input: Record<string, unknown>,
  options: BrokerInvokeOptions = {},
): BrokerInvocationResult {
  const root = canonicalMainframeRoot(configuredBrokerRoot());
  const contract = loadReviewedContract(root, canonicalId);
  return invokeReviewedContract(root, contract, input, options);
}

/**
 * Execute trusted Bash text with MAINFRAME sourced.
 *
 * This is an explicitly unbrokered escape hatch for application-owned code.
 * Never pass agent-, model-, or user-generated shell text to this API.
 */
export function execBash(script: string, options: ExecOptions = {}): ExecResult {
  const root = options.env?.MAINFRAME_ROOT || config.mainframeRoot;
  const timeout = options.timeout ?? config.timeout;

  // Build the full script with MAINFRAME sourced
  // Force a full library load: bindings call arbitrary registry functions,
  // and a lean MAINFRAME_LIBS leaked from the parent environment silently
  // leaves most binding-callable functions undefined.
  const fullScript = `
export MAINFRAME_LIBS="all"
source "$MAINFRAME_ROOT/lib/common.sh" 2>/dev/null || {
  echo "ERROR: Failed to source MAINFRAME" >&2
  exit 1
}
${script}
`;

  const env = protectedExecutionEnvironment(options.env);
  env.MAINFRAME_ROOT = root;
  env.MAINFRAME_OUTPUT = config.outputMode;

  try {
    const result: SpawnSyncReturns<Buffer> = spawnSync(
      configuredShell(),
      [...PROTECTED_BASH_ARGS, fullScript],
      {
        env,
        timeout,
        cwd: options.cwd,
        stdio: ["pipe", "pipe", "pipe"],
        maxBuffer: 50 * 1024 * 1024, // 50MB
      },
    );

    return {
      stdout: result.stdout?.toString("utf-8") ?? "",
      stderr: result.stderr?.toString("utf-8") ?? "",
      exitCode: result.status ?? 1,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      stdout: "",
      stderr: `Execution error: ${message}`,
      exitCode: 1,
    };
  }
}

/**
 * Call a reviewed stable-core MAINFRAME function and return the result.
 *
 * The Bash name is resolved through MANIFEST.json and positional arguments are
 * mapped through its reviewed call_shape before the canonical broker runs.
 * Unknown names and non-stable-core exports fail closed without shell lookup.
 */
export function callFunction<T = string>(
  funcName: string,
  args: (string | number | boolean)[] = [],
): MainframeResult<T> {
  if (!FUNCTION_NAME_PATTERN.test(funcName)) {
    return {
      success: false,
      error: `Invalid MAINFRAME function name: ${funcName}`,
      raw: "",
    };
  }
  try {
    const root = canonicalMainframeRoot(configuredBrokerRoot());
    const contract = resolveFunctionContract(root, funcName);
    const input = positionalInput(contract, args);
    const invocation = invokeReviewedContract(root, contract, input);
    const raw = contract.resultKind === "stdout" ? invocation.stdout : "";

    if (!invocation.controlPlane.resultAvailable || invocation.envelope === null) {
      return {
        success: false,
        error: `Durable result is unavailable (outcome=${invocation.controlPlane.outcome ?? invocation.controlPlane.status})`,
        raw,
      };
    }
    if (!invocation.envelope.ok) {
      return {
        success: false,
        error:
          invocation.envelope.error ||
          invocation.stderr.trim() ||
          `Function ${funcName} failed with exit code ${invocation.envelope.exit_code}`,
        raw,
      };
    }

    // Retain USOP decoding for callers that select a structured output mode,
    // but do not mistake an ordinary JSON value for a USOP envelope.
    if (
      config.outputMode === "json" ||
      config.outputMode === "minimal" ||
      config.outputMode === "debug"
    ) {
      try {
        const envelope = JSON.parse(raw) as UsopEnvelope<T>;
        if (typeof envelope.ok === "boolean") {
          if (envelope.ok === false) {
            return {
              success: false,
              error: envelope.error || "Unknown error",
              raw,
            };
          }
          return {
            success: true,
            data: envelope.data as T,
            raw,
          };
        }
      } catch {
        // Ordinary raw output is the historical public result shape.
      }
    }

    return {
        success: true,
        data: raw as T,
        raw,
      };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
      raw: "",
    };
  }
}

/**
 * Call a MAINFRAME function and return raw output (no JSON parsing)
 */
export function callFunctionRaw(funcName: string, args: (string | number | boolean)[] = []): string {
  const savedMode = config.outputMode;
  config.outputMode = "raw";

  try {
    const result = callFunction<string>(funcName, args);
    return result.success ? result.data : "";
  } finally {
    config.outputMode = savedMode;
  }
}

/**
 * Execute a bash expression and return the output
 */
export function evalBash(expression: string): string {
  const result = execBash(`printf '%s' "${expression}"`);
  return result.stdout;
}

// =============================================================================
// Initialization
// =============================================================================

// Auto-detect MAINFRAME root on module load
const detectedRoot = detectMainframeRoot();
if (detectedRoot) {
  config.mainframeRoot = detectedRoot;
}

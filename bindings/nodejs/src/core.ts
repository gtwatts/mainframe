/**
 * MAINFRAME Node.js Bindings - Core Module
 *
 * Provides subprocess wrapper for calling MAINFRAME bash functions
 * with proper error handling and USOP JSON response parsing.
 */

import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

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

/** Configuration options for MAINFRAME */
export interface MainframeConfig {
  /** Path to MAINFRAME root directory */
  mainframeRoot: string;
  /** Output mode: 'raw' | 'json' | 'minimal' | 'debug' */
  outputMode: "raw" | "json" | "minimal" | "debug";
  /** Timeout in milliseconds for bash execution */
  timeout: number;
  /** Shell to use (default: /bin/bash) */
  shell: string;
}

// =============================================================================
// Configuration
// =============================================================================

const DEFAULT_CONFIG: MainframeConfig = {
  mainframeRoot: process.env.MAINFRAME_ROOT || join(homedir(), ".mainframe"),
  outputMode: "json",
  timeout: 30000,
  shell: "/bin/bash",
};

let config: MainframeConfig = { ...DEFAULT_CONFIG };

/**
 * Get the current MAINFRAME configuration
 */
export function getConfig(): MainframeConfig {
  return { ...config };
}

/**
 * Update MAINFRAME configuration
 */
export function setConfig(newConfig: Partial<MainframeConfig>): void {
  config = { ...config, ...newConfig };
}

/**
 * Detect MAINFRAME installation path
 * Checks: MAINFRAME_ROOT env var -> ~/.mainframe -> /opt/mainframe
 */
export function detectMainframeRoot(): string | null {
  const candidates = [
    process.env.MAINFRAME_ROOT,
    join(homedir(), ".mainframe"),
    "/opt/mainframe",
    "/usr/local/mainframe",
  ].filter((p): p is string => typeof p === "string");

  for (const candidate of candidates) {
    const commonPath = join(candidate, "lib", "common.sh");
    if (existsSync(commonPath)) {
      return candidate;
    }
  }

  return null;
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

/**
 * Execute a bash script with MAINFRAME sourced
 */
export function execBash(script: string, options: ExecOptions = {}): ExecResult {
  const root = config.mainframeRoot;
  const timeout = options.timeout ?? config.timeout;

  // Build the full script with MAINFRAME sourced
  const fullScript = `
source "${root}/lib/common.sh" 2>/dev/null || {
  echo "ERROR: Failed to source MAINFRAME" >&2
  exit 1
}
export MAINFRAME_OUTPUT="${config.outputMode}"
${script}
`;

  const env = {
    ...process.env,
    MAINFRAME_ROOT: root,
    MAINFRAME_OUTPUT: config.outputMode,
    ...options.env,
  };

  try {
    const result: SpawnSyncReturns<Buffer> = spawnSync(config.shell, ["-c", fullScript], {
      env,
      timeout,
      cwd: options.cwd,
      stdio: ["pipe", "pipe", "pipe"],
      maxBuffer: 50 * 1024 * 1024, // 50MB
    });

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
 * Call a MAINFRAME function and return the result
 */
export function callFunction<T = string>(
  funcName: string,
  args: (string | number | boolean)[] = [],
): MainframeResult<T> {
  // Escape arguments for shell
  const escapedArgs = args.map((arg) => {
    const str = String(arg);
    // Use single quotes and escape any single quotes within
    return `'${str.replace(/'/g, "'\\''")}'`;
  });

  const script = `${funcName} ${escapedArgs.join(" ")}`;
  const result = execBash(script);

  const raw = result.stdout.trim();

  // Check for execution errors
  if (result.exitCode !== 0 && !raw) {
    return {
      success: false,
      error: result.stderr.trim() || `Function ${funcName} failed with exit code ${result.exitCode}`,
      raw: "",
    };
  }

  // Try to parse as USOP JSON if in JSON mode
  if (config.outputMode === "json" || config.outputMode === "minimal" || config.outputMode === "debug") {
    try {
      const envelope = JSON.parse(raw) as UsopEnvelope<T>;
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
    } catch {
      // Not valid JSON, fall through to raw handling
    }
  }

  // Raw mode or non-JSON output
  return {
    success: result.exitCode === 0,
    data: raw as T,
    raw,
    ...(result.exitCode !== 0 && { error: result.stderr.trim() || "Command failed" }),
  } as MainframeResult<T>;
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

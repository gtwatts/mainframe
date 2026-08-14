/**
 * Internal compatibility adapter for the package's fixed-name typed wrappers.
 *
 * This module is deliberately absent from the package entry point. It is not
 * an agent-controlled dispatch API: wrapper arguments are shell-quoted and the
 * function name is a source-code constant at every call site. Execution still
 * uses core's protected Bash environment, but it does not use broker policy,
 * confinement, contract review, or canonical invocation auditing.
 */

import { execBash, type MainframeResult } from "../core.js";

const LEGACY_FUNCTION_NAME_PATTERN = /^[A-Za-z_][A-Za-z0-9_:]*$/;

function quoteLegacyArgument(value: string | number | boolean): string {
  const text = String(value);
  if (text.includes("\0")) {
    throw new TypeError("Legacy wrapper arguments cannot contain NUL bytes");
  }
  return `'${text.replace(/'/g, "'\\''")}'`;
}

function executeLegacyFixedFunction(
  functionName: string,
  args: (string | number | boolean)[],
): { stdout: string; stderr: string; exitCode: number } {
  if (!LEGACY_FUNCTION_NAME_PATTERN.test(functionName)) {
    throw new TypeError(`Invalid fixed legacy function name: ${functionName}`);
  }
  const quoted = args.map(quoteLegacyArgument);
  return execBash(`${functionName}${quoted.length ? ` ${quoted.join(" ")}` : ""}`);
}

/** @internal Used only by fixed-name typed convenience wrappers. */
export function callLegacyFixedFunction<T = string>(
  functionName: string,
  args: (string | number | boolean)[] = [],
): MainframeResult<T> {
  const result = executeLegacyFixedFunction(functionName, args);
  // Preserve the historical Node convenience-wrapper behavior: all leading
  // and trailing whitespace from Bash output is removed.
  const raw = result.stdout.trim();
  if (result.exitCode !== 0) {
    return {
      success: false,
      error:
        result.stderr.trim() ||
        `Function ${functionName} failed with exit code ${result.exitCode}`,
      raw,
    };
  }
  return { success: true, data: raw as T, raw };
}

/** @internal Used only by fixed-name typed convenience wrappers. */
export function callLegacyFixedFunctionRaw(
  functionName: string,
  args: (string | number | boolean)[] = [],
): string {
  const result = callLegacyFixedFunction<string>(functionName, args);
  return result.success ? result.data : "";
}

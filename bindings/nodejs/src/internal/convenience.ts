/** Fixed-name compatibility router: reviewed exports are always durable. */

import {
  callFunction as callDurableFunction,
  callFunctionRaw as callDurableFunctionRaw,
  type MainframeResult,
} from "../core.js";
import {
  callLegacyFixedFunction,
  callLegacyFixedFunctionRaw,
} from "./legacy.js";

const REVIEWED_NAMES = new Set([
  "array_contains", "array_join", "is_numeric", "output_json", "output_success",
  "usop_error_validation", "path_sanitize", "is_empty", "to_lower", "to_upper",
  "trim_left", "trim_right", "json_array", "json_escape", "json_get", "json_merge",
  "json_object", "json_string", "json_valid", "validate_email", "validate_int",
  "validate_json", "validate_path", "validate_regex", "validate_semver", "validate_url",
]);

export function callFixedConvenience<T = string>(
  functionName: string,
  args: (string | number | boolean)[] = [],
): MainframeResult<T> {
  return REVIEWED_NAMES.has(functionName)
    ? callDurableFunction<T>(functionName, args)
    : callLegacyFixedFunction<T>(functionName, args);
}

export function callFixedConvenienceRaw(
  functionName: string,
  args: (string | number | boolean)[] = [],
): string {
  return REVIEWED_NAMES.has(functionName)
    ? callDurableFunctionRaw(functionName, args)
    : callLegacyFixedFunctionRaw(functionName, args);
}

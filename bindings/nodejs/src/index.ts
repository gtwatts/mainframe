/**
 * MAINFRAME Node.js/Bun Bindings
 *
 * TypeScript wrappers for MAINFRAME pure bash function library.
 * Provides JSON generation, validation, and utility functions.
 *
 * @example
 * import { jsonObject, validateEmail, uuid } from 'mainframe-bash'
 *
 * const obj = jsonObject({ name: "John", age: 30 })
 * const isValid = validateEmail("test@example.com")
 * const id = uuid()
 *
 * @packageDocumentation
 */

// =============================================================================
// Core Exports
// =============================================================================

export {
  // Configuration
  getConfig,
  setConfig,
  type MainframeConfig,

  // Detection
  detectMainframeRoot,
  verifyInstallation,

  // Execution
  execBash,
  invokeCanonical,
  callFunction,
  callFunctionRaw,
  evalBash,

  // Types
  type UsopEnvelope,
  type MainframeResult,
  type BrokerEnvelopeV1,
  type BrokerReceiptV1,
  type ControlPlaneInvocationV1,
  type BrokerInvocationResult,
  type BrokerInvokeOptions,
} from "./core.js";

// =============================================================================
// JSON Exports
// =============================================================================

export {
  // Object/Array creation
  jsonObject,
  jsonArray,
  jsonArrayTyped,

  // Value creation
  jsonEscape,
  jsonString,
  jsonNumber,
  jsonBool,
  jsonNull,
  jsonValue,

  // Manipulation
  jsonMerge,
  jsonGet,
  jsonSet,

  // Builder
  JsonBuilder,
  json,

  // Types
  type JsonValueType,
  type TypedEntry,
} from "./json.js";

// =============================================================================
// Validation Exports
// =============================================================================

export {
  // Type validation
  validateInt,
  validateFloat,
  validateBool,
  validateUuid,
  validateHex,

  // Format validation
  validateEmail,
  validateUrl,
  validateDomain,
  validateIpv4,
  validateIpv6,
  validateDate,
  validateTime,
  validateSemver,

  // Path validation
  validatePath,
  validatePathSafe,
  validateFilename,
  validatePathChars,

  // Sanitization
  sanitizeShellArg,
  sanitizeFilename,
  sanitizeSql,
  sanitizeHtml,
  sanitizeJson,

  // Complex validation
  validateRegex,
  validateLength,
  validateEnum,

  // Convenience
  validators,
  type ValidationResult,
} from "./validation.js";

// =============================================================================
// Utility Exports
// =============================================================================

export {
  // UUID and Random
  uuid,
  randomString,
  randomHex,
  randomBytes,
  randomRange,
  randomToken,
  generatePassword,

  // Timestamps
  now,
  nowIso,
  nowMs,
  nowRfc2822,
  timestamp,
  timestampIso,
  epoch,
  epochMs,
  parseIso,
  parseDate,

  // Logging
  logInfo,
  logWarn,
  logError,
  logDebug,
  success,
  failure,
  type LogLevel,

  // Hashing
  md5,
  sha1,
  sha256,
  sha512,
  hmacSha256,

  // Encoding
  base64Encode,
  base64Decode,
  hexEncode,
  hexDecode,
  urlEncode,
  urlDecode,

  // String utilities
  trimString,
  toLower,
  toUpper,
  capitalize,
  contains,
  startsWith,
  endsWith,

  // System utilities
  commandExists,
  commandPath,
  currentUser,
  getHostname,
  getOs,

  // Formatting
  formatBytes,
  formatDuration,
  formatNumber,
  formatPercent,
} from "./utils.js";

// =============================================================================
// Default Export
// =============================================================================

import { verifyInstallation, getConfig, setConfig, execBash } from "./core.js";
import { jsonObject, jsonArray, json } from "./json.js";
import { validateEmail, validateUrl, sanitizeHtml, validators } from "./validation.js";
import { uuid, timestamp, nowIso, logInfo, logError, logWarn } from "./utils.js";

/**
 * MAINFRAME default export with commonly used functions
 */
const mainframe = {
  // Core
  verifyInstallation,
  getConfig,
  setConfig,
  execBash,

  // JSON
  jsonObject,
  jsonArray,
  json,

  // Validation
  validateEmail,
  validateUrl,
  sanitizeHtml,
  validators,

  // Utils
  uuid,
  timestamp,
  nowIso,
  logInfo,
  logError,
  logWarn,
};

export default mainframe;

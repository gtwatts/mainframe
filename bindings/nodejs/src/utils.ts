/**
 * MAINFRAME Node.js Bindings - Utilities Module
 *
 * TypeScript wrappers for MAINFRAME utility functions.
 * Calls functions from pure-util.sh, datetime.sh, crypto.sh, common.sh
 */

import {
  callLegacyFixedFunction as callFunction,
  callLegacyFixedFunctionRaw as callFunctionRaw,
} from "./internal/legacy.js";

// =============================================================================
// UUID and Random
// =============================================================================

/**
 * Generate a UUID v4
 *
 * @example
 * uuid()  // "550e8400-e29b-41d4-a716-446655440000"
 */
export function uuid(): string {
  return callFunctionRaw("uuid", []);
}

/**
 * Generate a random string
 *
 * @example
 * randomString(16)  // "a1b2c3d4e5f6g7h8"
 */
export function randomString(length: number = 16): string {
  return callFunctionRaw("random_string", [length]);
}

/**
 * Generate a random hex string
 *
 * @example
 * randomHex(8)  // "a1b2c3d4"
 */
export function randomHex(length: number = 32): string {
  return callFunctionRaw("random_hex", [length]);
}

/**
 * Generate random bytes as hex
 *
 * @example
 * randomBytes(16)  // "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
 */
export function randomBytes(count: number = 16): string {
  return callFunctionRaw("random_bytes", [count]);
}

/**
 * Generate a random integer in range
 *
 * @example
 * randomRange(1, 100)  // 42
 */
export function randomRange(min: number, max: number): number {
  const result = callFunctionRaw("random_range", [min, max]);
  return parseInt(result, 10);
}

/**
 * Generate a URL-safe random token
 *
 * @example
 * randomToken(32)  // "aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
 */
export function randomToken(length: number = 32): string {
  return callFunctionRaw("random_token", [length]);
}

/**
 * Generate a random password
 *
 * @example
 * generatePassword(16)            // "aB3dEf6hIj9kLmNo"
 * generatePassword(16, "special") // "aB3!dEf@6hIj#9kL"
 */
export function generatePassword(length: number = 16, mode?: "alphanumeric" | "special"): string {
  const args: (string | number)[] = [length];
  if (mode) args.push(mode);
  return callFunctionRaw("generate_password", args);
}

// =============================================================================
// Timestamps and DateTime
// =============================================================================

/**
 * Get current Unix timestamp (seconds since epoch)
 *
 * @example
 * now()  // 1737123045
 */
export function now(): number {
  const result = callFunctionRaw("now", []);
  return parseInt(result, 10);
}

/**
 * Get current timestamp as ISO 8601 string
 *
 * @example
 * nowIso()  // "2026-01-17T12:30:45+0000"
 */
export function nowIso(): string {
  return callFunctionRaw("now_iso", []);
}

/**
 * Get current timestamp in milliseconds
 *
 * @example
 * nowMs()  // 1737123045000
 */
export function nowMs(): number {
  const result = callFunctionRaw("now_ms", []);
  return parseInt(result, 10);
}

/**
 * Get current timestamp as RFC 2822 string (email format)
 *
 * @example
 * nowRfc2822()  // "Fri, 17 Jan 2026 12:30:45 +0000"
 */
export function nowRfc2822(): string {
  return callFunctionRaw("now_rfc2822", []);
}

/**
 * Get current timestamp formatted (MAINFRAME format)
 *
 * @example
 * timestamp()  // "2026-01-17 12:30:45"
 */
export function timestamp(): string {
  return callFunctionRaw("timestamp", []);
}

/**
 * Get current timestamp as ISO 8601 string (alias for nowIso)
 *
 * @example
 * timestampIso()  // "2026-01-17T12:30:45Z"
 */
export function timestampIso(): string {
  return callFunctionRaw("timestamp_iso", []);
}

/**
 * Get current Unix epoch timestamp
 *
 * @example
 * epoch()  // 1737123045
 */
export function epoch(): number {
  const result = callFunctionRaw("epoch", []);
  return parseInt(result, 10);
}

/**
 * Get current epoch timestamp in milliseconds
 *
 * @example
 * epochMs()  // 1737123045123
 */
export function epochMs(): number {
  const result = callFunctionRaw("epoch_ms", []);
  return parseInt(result, 10);
}

/**
 * Parse ISO 8601 string to epoch
 *
 * @example
 * parseIso("2024-01-15T10:30:00Z")  // 1705315800
 */
export function parseIso(isoString: string): number {
  const result = callFunctionRaw("parse_iso", [isoString]);
  return parseInt(result, 10);
}

/**
 * Parse date string (YYYY-MM-DD) to epoch
 *
 * @example
 * parseDate("2024-01-15")  // 1705276800
 */
export function parseDate(dateString: string): number {
  const result = callFunctionRaw("parse_date", [dateString]);
  return parseInt(result, 10);
}

// =============================================================================
// Logging
// =============================================================================

/** Log levels */
export type LogLevel = "debug" | "info" | "warn" | "error" | "fatal";

/**
 * Log an info message
 *
 * @example
 * logInfo("Application started")
 */
export function logInfo(message: string): void {
  callFunction("log::info", [message]);
}

/**
 * Log a warning message
 *
 * @example
 * logWarn("Configuration file not found, using defaults")
 */
export function logWarn(message: string): void {
  callFunction("log::warn", [message]);
}

/**
 * Log an error message
 *
 * @example
 * logError("Failed to connect to database")
 */
export function logError(message: string): void {
  callFunction("log::error", [message]);
}

/**
 * Log a debug message
 *
 * @example
 * logDebug("Processing item: 42")
 */
export function logDebug(message: string): void {
  callFunction("log_debug", [message]);
}

/**
 * Log a success message with [OK] prefix
 *
 * @example
 * success("Database connected")
 */
export function success(message: string): void {
  callFunction("success", [message]);
}

/**
 * Log a failure message with [FAIL] prefix
 *
 * @example
 * failure("Authentication failed")
 */
export function failure(message: string): void {
  callFunction("failure", [message]);
}

// =============================================================================
// Hashing
// =============================================================================

/**
 * Calculate MD5 hash of a string
 *
 * @example
 * md5("hello world")  // "5eb63bbbe01eeed093cb22bb8f5acdc3"
 */
export function md5(value: string): string {
  return callFunctionRaw("md5", [value]);
}

/**
 * Calculate SHA-1 hash of a string
 *
 * @example
 * sha1("hello world")  // "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed"
 */
export function sha1(value: string): string {
  return callFunctionRaw("sha1", [value]);
}

/**
 * Calculate SHA-256 hash of a string
 *
 * @example
 * sha256("hello world")  // "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
 */
export function sha256(value: string): string {
  return callFunctionRaw("sha256", [value]);
}

/**
 * Calculate SHA-512 hash of a string
 *
 * @example
 * sha512("hello world")  // "309ecc489c12d6eb4cc40f50c902f2b4d0ed77ee..."
 */
export function sha512(value: string): string {
  return callFunctionRaw("sha512", [value]);
}

/**
 * HMAC-SHA256
 *
 * @example
 * hmacSha256("secret", "message")
 */
export function hmacSha256(key: string, message: string): string {
  return callFunctionRaw("hmac_sha256", [key, message]);
}

// =============================================================================
// Encoding
// =============================================================================

/**
 * Base64 encode a string
 *
 * @example
 * base64Encode("hello world")  // "aGVsbG8gd29ybGQ="
 */
export function base64Encode(value: string): string {
  return callFunctionRaw("base64_encode", [value]);
}

/**
 * Base64 decode a string
 *
 * @example
 * base64Decode("aGVsbG8gd29ybGQ=")  // "hello world"
 */
export function base64Decode(value: string): string {
  return callFunctionRaw("base64_decode", [value]);
}

/**
 * Hex encode a string
 *
 * @example
 * hexEncode("hello")  // "68656c6c6f"
 */
export function hexEncode(value: string): string {
  return callFunctionRaw("hex_encode", [value]);
}

/**
 * Hex decode a string
 *
 * @example
 * hexDecode("68656c6c6f")  // "hello"
 */
export function hexDecode(value: string): string {
  return callFunctionRaw("hex_decode", [value]);
}

/**
 * URL encode a string
 *
 * @example
 * urlEncode("hello world")  // "hello%20world"
 */
export function urlEncode(value: string): string {
  return callFunctionRaw("urlencode", [value]);
}

/**
 * URL decode a string
 *
 * @example
 * urlDecode("hello%20world")  // "hello world"
 */
export function urlDecode(value: string): string {
  return callFunctionRaw("urldecode", [value]);
}

// =============================================================================
// String Utilities
// =============================================================================

/**
 * Trim whitespace from both ends of a string
 *
 * @example
 * trimString("  hello  ")  // "hello"
 */
export function trimString(value: string): string {
  return callFunctionRaw("trim_string", [value]);
}

/**
 * Convert string to lowercase
 *
 * @example
 * toLower("HELLO")  // "hello"
 */
export function toLower(value: string): string {
  return callFunctionRaw("to_lower", [value]);
}

/**
 * Convert string to uppercase
 *
 * @example
 * toUpper("hello")  // "HELLO"
 */
export function toUpper(value: string): string {
  return callFunctionRaw("to_upper", [value]);
}

/**
 * Capitalize first letter
 *
 * @example
 * capitalize("hello")  // "Hello"
 */
export function capitalize(value: string): string {
  return callFunctionRaw("capitalize", [value]);
}

/**
 * Check if string contains substring
 *
 * @example
 * contains("hello world", "world")  // true
 */
export function contains(str: string, substr: string): boolean {
  const result = callFunction<string>("contains", [str, substr]);
  return result.success;
}

/**
 * Check if string starts with prefix
 *
 * @example
 * startsWith("hello", "hel")  // true
 */
export function startsWith(str: string, prefix: string): boolean {
  const result = callFunction<string>("starts_with", [str, prefix]);
  return result.success;
}

/**
 * Check if string ends with suffix
 *
 * @example
 * endsWith("hello", "lo")  // true
 */
export function endsWith(str: string, suffix: string): boolean {
  const result = callFunction<string>("ends_with", [str, suffix]);
  return result.success;
}

// =============================================================================
// System Utilities
// =============================================================================

/**
 * Check if a command exists
 *
 * @example
 * commandExists("git")  // true
 */
export function commandExists(cmd: string): boolean {
  const result = callFunction<string>("cmd_exists", [cmd]);
  return result.success;
}

/**
 * Get the path of a command
 *
 * @example
 * commandPath("bash")  // "/bin/bash"
 */
export function commandPath(cmd: string): string {
  return callFunctionRaw("cmd_path", [cmd]);
}

/**
 * Get current username
 *
 * @example
 * currentUser()  // "gordon"
 */
export function currentUser(): string {
  return callFunctionRaw("current_user", []);
}

/**
 * Get hostname
 *
 * @example
 * getHostname()  // "workstation"
 */
export function getHostname(): string {
  return callFunctionRaw("get_hostname", []);
}

/**
 * Get OS name
 *
 * @example
 * getOs()  // "linux"
 */
export function getOs(): string {
  return callFunctionRaw("get_os", []);
}

// =============================================================================
// Formatting
// =============================================================================

/**
 * Format bytes to human readable string
 *
 * @example
 * formatBytes(1048576)  // "1.0MB"
 */
export function formatBytes(bytes: number): string {
  return callFunctionRaw("format_bytes", [bytes]);
}

/**
 * Format duration in seconds to human readable string
 *
 * @example
 * formatDuration(3661)  // "1h 1m 1s"
 */
export function formatDuration(seconds: number): string {
  return callFunctionRaw("format_duration", [seconds]);
}

/**
 * Format number with thousands separator
 *
 * @example
 * formatNumber(1234567)  // "1,234,567"
 */
export function formatNumber(n: number): string {
  // Bash's printf grouping flag is locale-dependent and returns an ungrouped
  // value under the C locale used by CI and many containers. Keep the binding's
  // documented comma-separated contract deterministic across platforms.
  return Math.trunc(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * Format percentage
 *
 * @example
 * formatPercent(75, 100)  // "75%"
 */
export function formatPercent(value: number, total: number): string {
  return callFunctionRaw("format_percent", [value, total]);
}

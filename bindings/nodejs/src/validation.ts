/**
 * MAINFRAME Node.js Bindings - Validation Module
 *
 * TypeScript wrappers for MAINFRAME validation and sanitization functions.
 * Calls validation.sh functions: validate_email, validate_url, sanitize_html, etc.
 */

import { callFunction, callFunctionRaw } from "./core.js";

// =============================================================================
// Type Validation
// =============================================================================

/**
 * Validate an integer with optional range
 *
 * @example
 * validateInt("42")           // true
 * validateInt("42", 0, 100)   // true
 * validateInt("150", 0, 100)  // false
 */
export function validateInt(
  value: string | number,
  min?: number,
  max?: number,
): boolean {
  const args: (string | number)[] = [String(value)];
  if (min !== undefined) args.push(min);
  if (max !== undefined) args.push(max);

  const result = callFunction<string>("validate_int", args);
  return result.success;
}

/**
 * Validate a floating point number
 *
 * @example
 * validateFloat("12.34")  // true
 * validateFloat("1e10")   // true
 * validateFloat("abc")    // false
 */
export function validateFloat(value: string | number): boolean {
  const result = callFunction<string>("validate_float", [String(value)]);
  return result.success;
}

/**
 * Validate a boolean value
 * Accepts: true/false/yes/no/1/0/on/off (case insensitive)
 *
 * @example
 * validateBool("true")   // true
 * validateBool("yes")    // true
 * validateBool("maybe")  // false
 */
export function validateBool(value: string): boolean {
  const result = callFunction<string>("validate_bool", [value]);
  return result.success;
}

/**
 * Validate UUID format (v1-v5)
 *
 * @example
 * validateUuid("550e8400-e29b-41d4-a716-446655440000")  // true
 * validateUuid("not-a-uuid")                            // false
 */
export function validateUuid(value: string): boolean {
  const result = callFunction<string>("validate_uuid", [value]);
  return result.success;
}

/**
 * Validate hexadecimal string
 *
 * @example
 * validateHex("deadbeef")      // true
 * validateHex("deadbeef", 8)   // true (exact length)
 * validateHex("xyz")           // false
 */
export function validateHex(value: string, length?: number): boolean {
  const args: (string | number)[] = [value];
  if (length !== undefined) args.push(length);

  const result = callFunction<string>("validate_hex", args);
  return result.success;
}

// =============================================================================
// Format Validation
// =============================================================================

/**
 * Validate email address (RFC 5322 simplified)
 *
 * @example
 * validateEmail("user@example.com")  // true
 * validateEmail("invalid")           // false
 */
export function validateEmail(email: string): boolean {
  const result = callFunction<string>("validate_email", [email]);
  return result.success;
}

/**
 * Validate URL format
 *
 * @example
 * validateUrl("https://example.com")           // true
 * validateUrl("ftp://files.com", "ftp,http")   // true
 * validateUrl("not-a-url")                     // false
 */
export function validateUrl(url: string, schemes?: string): boolean {
  const args = [url];
  if (schemes) args.push(schemes);

  const result = callFunction<string>("validate_url", args);
  return result.success;
}

/**
 * Validate domain name format
 *
 * @example
 * validateDomain("example.com")  // true
 * validateDomain("localhost")    // false (no TLD)
 */
export function validateDomain(domain: string): boolean {
  const result = callFunction<string>("validate_domain", [domain]);
  return result.success;
}

/**
 * Validate IPv4 address
 *
 * @example
 * validateIpv4("192.168.1.1")  // true
 * validateIpv4("999.1.1.1")    // false
 */
export function validateIpv4(ip: string): boolean {
  const result = callFunction<string>("validate_ipv4", [ip]);
  return result.success;
}

/**
 * Validate IPv6 address
 *
 * @example
 * validateIpv6("::1")                           // true
 * validateIpv6("2001:db8::1")                   // true
 * validateIpv6("2001:db8:85a3::8a2e:370:7334")  // true
 */
export function validateIpv6(ip: string): boolean {
  const result = callFunction<string>("validate_ipv6", [ip]);
  return result.success;
}

/**
 * Validate date format YYYY-MM-DD
 *
 * @example
 * validateDate("2024-01-15")  // true
 * validateDate("2024-02-30")  // false (invalid day)
 */
export function validateDate(date: string): boolean {
  const result = callFunction<string>("validate_date", [date]);
  return result.success;
}

/**
 * Validate time format HH:MM:SS
 *
 * @example
 * validateTime("12:30:00")  // true
 * validateTime("25:00:00")  // false
 */
export function validateTime(time: string): boolean {
  const result = callFunction<string>("validate_time", [time]);
  return result.success;
}

/**
 * Validate semantic version
 *
 * @example
 * validateSemver("1.2.3")        // true
 * validateSemver("v1.2.3")       // true
 * validateSemver("1.2.3-beta")   // true
 * validateSemver("1.2")          // false
 */
export function validateSemver(version: string): boolean {
  const result = callFunction<string>("validate_semver", [version]);
  return result.success;
}

// =============================================================================
// Path Validation
// =============================================================================

/**
 * Validate path exists with optional type check
 *
 * @example
 * validatePath("/etc/hosts", "file")  // true
 * validatePath("/tmp", "dir")         // true
 */
export function validatePath(
  path: string,
  type?: "file" | "dir" | "any",
): boolean {
  const args = [path];
  if (type) args.push(type);

  const result = callFunction<string>("validate_path", args);
  return result.success;
}

/**
 * Validate path is safe (no traversal attacks)
 *
 * @example
 * validatePathSafe("./file.txt")           // true
 * validatePathSafe("../../../etc/passwd")  // false
 */
export function validatePathSafe(path: string, baseDir?: string): boolean {
  const args = [path];
  if (baseDir) args.push(baseDir);

  const result = callFunction<string>("validate_path_safe", args);
  return result.success;
}

/**
 * Validate filename (no path components)
 *
 * @example
 * validateFilename("file.txt")      // true
 * validateFilename("../file.txt")   // false
 * validateFilename("-file.txt")     // false (starts with dash)
 */
export function validateFilename(name: string): boolean {
  const result = callFunction<string>("validate_filename", [name]);
  return result.success;
}

/**
 * Validate path contains only safe characters
 *
 * @example
 * validatePathChars("/home/user/file.txt")  // true
 * validatePathChars("/home/user/file;rm")   // false
 */
export function validatePathChars(path: string): boolean {
  const result = callFunction<string>("validate_path_chars", [path]);
  return result.success;
}

// =============================================================================
// Sanitization
// =============================================================================

/**
 * Sanitize value for safe shell argument
 *
 * @example
 * sanitizeShellArg("hello world")  // 'hello world' (or properly escaped)
 * sanitizeShellArg("$(whoami)")    // \$\(whoami\)
 */
export function sanitizeShellArg(value: string): string {
  return callFunctionRaw("sanitize_shell_arg", [value]);
}

/**
 * Sanitize filename by removing dangerous characters
 *
 * @example
 * sanitizeFilename("my/file.txt")      // my_file.txt
 * sanitizeFilename("file;rm -rf /")    // file_rm_-rf__
 */
export function sanitizeFilename(name: string, replacement?: string): string {
  const args = [name];
  if (replacement) args.push(replacement);

  return callFunctionRaw("sanitize_filename", args);
}

/**
 * Sanitize for SQL (basic escaping)
 * WARNING: Prefer parameterized queries in production
 *
 * @example
 * sanitizeSql("O'Brien")  // O''Brien
 */
export function sanitizeSql(value: string): string {
  return callFunctionRaw("sanitize_sql", [value]);
}

/**
 * Sanitize for HTML (entity escaping)
 *
 * @example
 * sanitizeHtml('<script>alert("xss")</script>')
 * // &lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;
 */
export function sanitizeHtml(value: string): string {
  return callFunctionRaw("sanitize_html", [value]);
}

/**
 * Sanitize for JSON string (escape special chars)
 *
 * @example
 * sanitizeJson('hello\nworld')  // hello\\nworld
 */
export function sanitizeJson(value: string): string {
  return callFunctionRaw("sanitize_json", [value]);
}

// =============================================================================
// Complex Validation
// =============================================================================

/**
 * Validate value against regex pattern
 *
 * @example
 * validateRegex("abc123", "^[a-z0-9]+$")  // true
 */
export function validateRegex(value: string, pattern: string): boolean {
  const result = callFunction<string>("validate_regex", [value, pattern]);
  return result.success;
}

/**
 * Validate string length
 *
 * @example
 * validateLength("hello", 1, 10)  // true
 * validateLength("hi", 5)         // false (min 5)
 */
export function validateLength(
  value: string,
  min?: number,
  max?: number,
): boolean {
  const args: (string | number)[] = [value];
  // Always push min if max is defined (to maintain positional args)
  if (min !== undefined || max !== undefined) {
    args.push(min !== undefined ? min : "");
  }
  if (max !== undefined) args.push(max);

  const result = callFunction<string>("validate_length", args);
  return result.success;
}

/**
 * Validate value is in list (enum)
 *
 * @example
 * validateEnum("red", ["red", "green", "blue"])  // true
 * validateEnum("yellow", ["red", "green"])       // false
 */
export function validateEnum(value: string, options: string[]): boolean {
  const result = callFunction<string>("validate_enum", [value, ...options]);
  return result.success;
}

// =============================================================================
// Convenience Validators
// =============================================================================

/** Validation result with error message */
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

/**
 * Validate with detailed error messages
 */
export const validators = {
  email: (value: string): ValidationResult => ({
    valid: validateEmail(value),
    error: validateEmail(value) ? undefined : "Invalid email format",
  }),

  url: (value: string): ValidationResult => ({
    valid: validateUrl(value),
    error: validateUrl(value) ? undefined : "Invalid URL format",
  }),

  uuid: (value: string): ValidationResult => ({
    valid: validateUuid(value),
    error: validateUuid(value) ? undefined : "Invalid UUID format",
  }),

  ipv4: (value: string): ValidationResult => ({
    valid: validateIpv4(value),
    error: validateIpv4(value) ? undefined : "Invalid IPv4 address",
  }),

  ipv6: (value: string): ValidationResult => ({
    valid: validateIpv6(value),
    error: validateIpv6(value) ? undefined : "Invalid IPv6 address",
  }),

  date: (value: string): ValidationResult => ({
    valid: validateDate(value),
    error: validateDate(value)
      ? undefined
      : "Invalid date format (expected YYYY-MM-DD)",
  }),

  semver: (value: string): ValidationResult => ({
    valid: validateSemver(value),
    error: validateSemver(value) ? undefined : "Invalid semantic version",
  }),
};

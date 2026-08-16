/**
 * MAINFRAME Node.js Bindings - JSON Module
 *
 * TypeScript wrappers for MAINFRAME JSON generation functions.
 * Calls json.sh functions: json_object, json_array, json_string, etc.
 */

import { callLegacyFixedFunctionRaw as callFunctionRaw } from "./internal/legacy.js";

// =============================================================================
// Types
// =============================================================================

/** Supported JSON value types for json_object */
export type JsonValueType = "string" | "number" | "bool" | "raw" | "auto";

/** Object entry with explicit type */
export interface TypedEntry {
  key: string;
  value: string | number | boolean;
  type?: JsonValueType;
}

// =============================================================================
// JSON Creation Functions
// =============================================================================

/**
 * Create a JSON object from key-value pairs
 *
 * @example
 * jsonObject({ name: "John", age: 30, active: true })
 * // {"name":"John","age":30,"active":true}
 *
 * @example
 * jsonObject([
 *   { key: "name", value: "John", type: "string" },
 *   { key: "age", value: 30, type: "number" },
 *   { key: "active", value: true, type: "bool" }
 * ])
 */
export function jsonObject(
  data: Record<string, string | number | boolean | null> | TypedEntry[],
): string {
  // Build arguments in MAINFRAME format: key=value or key:type=value
  const args: string[] = [];

  if (Array.isArray(data)) {
    // TypedEntry array format
    for (const entry of data) {
      const { key, value, type = "auto" } = entry;
      if (type === "auto") {
        args.push(`${key}=${value}`);
      } else {
        args.push(`${key}:${type}=${value}`);
      }
    }
  } else {
    // Record format - auto-detect types
    for (const [key, value] of Object.entries(data)) {
      if (value === null) {
        args.push(`${key}:raw=null`);
      } else if (typeof value === "boolean") {
        args.push(`${key}:bool=${value}`);
      } else if (typeof value === "number") {
        args.push(`${key}:number=${value}`);
      } else {
        args.push(`${key}=${value}`);
      }
    }
  }

  return callFunctionRaw("json_object", args);
}

/**
 * Create a JSON array from values
 *
 * @example
 * jsonArray(["a", "b", "c"])
 * // ["a","b","c"]
 *
 * @example
 * jsonArray([1, 2, 3])
 * // [1,2,3]
 */
export function jsonArray(values: (string | number | boolean)[]): string {
  return callFunctionRaw("json_array", values.map(String));
}

/**
 * Create a typed JSON array
 *
 * @example
 * jsonArrayTyped("number", [1, 2, 3])
 * // [1,2,3]
 *
 * @example
 * jsonArrayTyped("string", ["a", "b"])
 * // ["a","b"]
 */
export function jsonArrayTyped(type: JsonValueType, values: (string | number | boolean)[]): string {
  return callFunctionRaw("json_array_typed", [type, ...values.map(String)]);
}

/**
 * Escape a string for JSON
 *
 * @example
 * jsonEscape('hello "world"')
 * // hello \"world\"
 */
export function jsonEscape(value: string): string {
  return callFunctionRaw("json_escape", [value]);
}

/**
 * Create a JSON string value (with quotes)
 *
 * @example
 * jsonString("hello")
 * // "hello"
 */
export function jsonString(value: string): string {
  return callFunctionRaw("json_string", [value]);
}

/**
 * Create a JSON number value
 *
 * @example
 * jsonNumber(42)
 * // 42
 */
export function jsonNumber(value: number): string {
  return callFunctionRaw("json_number", [value]);
}

/**
 * Create a JSON boolean value
 *
 * @example
 * jsonBool(true)
 * // true
 */
export function jsonBool(value: boolean): string {
  return callFunctionRaw("json_bool", [value ? "true" : "false"]);
}

/**
 * Create a JSON null value
 */
export function jsonNull(): string {
  return "null";
}

/**
 * Auto-detect type and create appropriate JSON value
 *
 * @example
 * jsonValue("hello")  // "hello"
 * jsonValue(42)       // 42
 * jsonValue(true)     // true
 * jsonValue(null)     // null
 */
export function jsonValue(value: string | number | boolean | null): string {
  if (value === null) {
    return "null";
  }
  return callFunctionRaw("json_value", [String(value)]);
}

// =============================================================================
// JSON Manipulation Functions
// =============================================================================

/**
 * Merge multiple JSON objects
 *
 * @example
 * jsonMerge('{"a":1}', '{"b":2}')
 * // {"a":1,"b":2}
 */
export function jsonMerge(...objects: string[]): string {
  return callFunctionRaw("json_merge", objects);
}

/**
 * Get a value from JSON by path
 *
 * @example
 * jsonGet('{"a":{"b":1}}', "a.b")
 * // 1
 */
export function jsonGet(json: string, path: string): string {
  return callFunctionRaw("json_get", [json, path]);
}

/**
 * Set a value in JSON by path
 *
 * @example
 * jsonSet('{"a":1}', "b", "2")
 * // {"a":1,"b":2}
 */
export function jsonSet(json: string, path: string, value: string): string {
  return callFunctionRaw("json_set", [json, path, value]);
}

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Build a complex JSON structure using a builder pattern
 */
export class JsonBuilder {
  private data: Record<string, string | number | boolean | null> = {};

  /**
   * Add a string value
   */
  string(key: string, value: string): this {
    this.data[key] = value;
    return this;
  }

  /**
   * Add a number value
   */
  number(key: string, value: number): this {
    this.data[key] = value;
    return this;
  }

  /**
   * Add a boolean value
   */
  bool(key: string, value: boolean): this {
    this.data[key] = value;
    return this;
  }

  /**
   * Add a null value
   */
  null(key: string): this {
    this.data[key] = null;
    return this;
  }

  /**
   * Build the JSON string
   */
  build(): string {
    return jsonObject(this.data);
  }
}

/**
 * Create a new JSON builder
 *
 * @example
 * const json = json()
 *   .string("name", "John")
 *   .number("age", 30)
 *   .bool("active", true)
 *   .build()
 */
export function json(): JsonBuilder {
  return new JsonBuilder();
}

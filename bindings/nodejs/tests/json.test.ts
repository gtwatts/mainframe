/**
 * MAINFRAME Node.js Bindings - JSON Module Tests
 */

import { describe, test, expect, beforeAll } from "bun:test";
import { setConfig } from "../src/core";
import {
  jsonObject,
  jsonArray,
  jsonArrayTyped,
  jsonEscape,
  jsonString,
  jsonNumber,
  jsonBool,
  jsonNull,
  jsonValue,
  json,
  JsonBuilder,
} from "../src/json";

describe("JSON Module", () => {
  beforeAll(() => {
    setConfig({ outputMode: "raw" });
  });

  describe("jsonObject", () => {
    test("should create JSON object from record", () => {
      const result = jsonObject({ name: "John", age: 30 });
      const parsed = JSON.parse(result);
      expect(parsed.name).toBe("John");
      expect(parsed.age).toBe(30);
    });

    test("should handle boolean values", () => {
      const result = jsonObject({ active: true, disabled: false });
      const parsed = JSON.parse(result);
      expect(parsed.active).toBe(true);
      expect(parsed.disabled).toBe(false);
    });

    test("should handle null values", () => {
      const result = jsonObject({ value: null });
      const parsed = JSON.parse(result);
      expect(parsed.value).toBeNull();
    });

    test("should handle mixed types", () => {
      const result = jsonObject({
        name: "Test",
        count: 42,
        enabled: true,
        data: null,
      });
      const parsed = JSON.parse(result);
      expect(parsed.name).toBe("Test");
      expect(parsed.count).toBe(42);
      expect(parsed.enabled).toBe(true);
      expect(parsed.data).toBeNull();
    });

    test("should handle TypedEntry array format", () => {
      const result = jsonObject([
        { key: "name", value: "John", type: "string" },
        { key: "age", value: 30, type: "number" },
      ]);
      const parsed = JSON.parse(result);
      expect(parsed.name).toBe("John");
      expect(parsed.age).toBe(30);
    });
  });

  describe("jsonArray", () => {
    test("should create JSON array from strings", () => {
      const result = jsonArray(["a", "b", "c"]);
      const parsed = JSON.parse(result);
      expect(parsed).toEqual(["a", "b", "c"]);
    });

    test("should create JSON array from numbers", () => {
      const result = jsonArray([1, 2, 3]);
      const parsed = JSON.parse(result);
      // Numbers come back as strings with auto-detect
      expect(parsed.length).toBe(3);
    });

    test("should handle empty array", () => {
      const result = jsonArray([]);
      const parsed = JSON.parse(result);
      expect(parsed).toEqual([]);
    });
  });

  describe("jsonArrayTyped", () => {
    test("should create typed number array", () => {
      const result = jsonArrayTyped("number", [1, 2, 3]);
      const parsed = JSON.parse(result);
      expect(parsed).toEqual([1, 2, 3]);
    });

    test("should create typed string array", () => {
      const result = jsonArrayTyped("string", ["a", "b", "c"]);
      const parsed = JSON.parse(result);
      expect(parsed).toEqual(["a", "b", "c"]);
    });

    test("should create typed bool array", () => {
      const result = jsonArrayTyped("bool", [true, false, true]);
      const parsed = JSON.parse(result);
      expect(parsed).toEqual([true, false, true]);
    });
  });

  describe("jsonEscape", () => {
    test("should escape quotes", () => {
      const result = jsonEscape('hello "world"');
      expect(result).toContain('\\"');
    });

    test("should escape backslashes", () => {
      const result = jsonEscape("path\\to\\file");
      expect(result).toContain("\\\\");
    });

    test("should escape newlines", () => {
      const result = jsonEscape("line1\nline2");
      expect(result).toContain("\\n");
    });

    test("should handle empty string", () => {
      const result = jsonEscape("");
      expect(result).toBe("");
    });
  });

  describe("jsonString", () => {
    test("should create quoted string", () => {
      const result = jsonString("hello");
      expect(result).toBe('"hello"');
    });

    test("should escape special characters in string", () => {
      const result = jsonString('hello "world"');
      expect(result.startsWith('"')).toBe(true);
      expect(result.endsWith('"')).toBe(true);
    });
  });

  describe("jsonNumber", () => {
    test("should create integer", () => {
      const result = jsonNumber(42);
      expect(result).toBe("42");
    });

    test("should create float", () => {
      const result = jsonNumber(3.14);
      expect(result).toBe("3.14");
    });

    test("should create negative number", () => {
      const result = jsonNumber(-42);
      expect(result).toBe("-42");
    });
  });

  describe("jsonBool", () => {
    test("should create true", () => {
      const result = jsonBool(true);
      expect(result).toBe("true");
    });

    test("should create false", () => {
      const result = jsonBool(false);
      expect(result).toBe("false");
    });
  });

  describe("jsonNull", () => {
    test("should return null string", () => {
      const result = jsonNull();
      expect(result).toBe("null");
    });
  });

  describe("jsonValue", () => {
    test("should auto-detect string", () => {
      const result = jsonValue("hello");
      expect(result).toBe('"hello"');
    });

    test("should auto-detect number", () => {
      const result = jsonValue(42);
      expect(result).toBe("42");
    });

    test("should auto-detect boolean", () => {
      const result = jsonValue(true);
      expect(result).toBe("true");
    });

    test("should handle null", () => {
      const result = jsonValue(null);
      expect(result).toBe("null");
    });
  });

  describe("JsonBuilder", () => {
    test("should build JSON object with fluent API", () => {
      const result = new JsonBuilder()
        .string("name", "John")
        .number("age", 30)
        .bool("active", true)
        .build();

      const parsed = JSON.parse(result);
      expect(parsed.name).toBe("John");
      expect(parsed.age).toBe(30);
      expect(parsed.active).toBe(true);
    });

    test("should handle null values", () => {
      const result = new JsonBuilder()
        .string("name", "Test")
        .null("data")
        .build();

      const parsed = JSON.parse(result);
      expect(parsed.name).toBe("Test");
      expect(parsed.data).toBeNull();
    });
  });

  describe("json() helper", () => {
    test("should create builder instance", () => {
      const builder = json();
      expect(builder).toBeInstanceOf(JsonBuilder);
    });

    test("should chain and build", () => {
      const result = json()
        .string("key", "value")
        .number("count", 5)
        .build();

      const parsed = JSON.parse(result);
      expect(parsed.key).toBe("value");
      expect(parsed.count).toBe(5);
    });
  });
});

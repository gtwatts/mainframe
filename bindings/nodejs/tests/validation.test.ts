/**
 * MAINFRAME Node.js Bindings - Validation Module Tests
 */

import "./setup";

import { describe, test, expect, beforeAll, setDefaultTimeout } from "bun:test";
import { setConfig } from "../src/core";
import {
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
  validateFilename,
  validatePathChars,

  // Sanitization
  sanitizeFilename,
  sanitizeHtml,
  sanitizeSql,
  sanitizeJson,

  // Complex validation
  validateRegex,
  validateLength,
  validateEnum,

  // Convenience
  validators,
} from "../src/validation";

// These assertions exercise the reviewed durable route, so each one may
// start a control-plane process. Keep the file bounded while allowing several
// sequential assertions on slower hosted runners.
setDefaultTimeout(15_000);

describe("Validation Module", () => {
  beforeAll(() => {
    setConfig({ outputMode: "raw" });
  });

  describe("Type Validation", () => {
    describe("validateInt", () => {
      test("should validate positive integers", () => {
        expect(validateInt("42")).toBe(true);
        expect(validateInt(42)).toBe(true);
      });

      test("should validate negative integers", () => {
        expect(validateInt("-42")).toBe(true);
        expect(validateInt(-42)).toBe(true);
      });

      test("should reject non-integers", () => {
        expect(validateInt("3.14")).toBe(false);
        expect(validateInt("abc")).toBe(false);
        expect(validateInt("")).toBe(false);
      });

      test("should validate with range", () => {
        expect(validateInt("50", 0, 100)).toBe(true);
        expect(validateInt("150", 0, 100)).toBe(false);
        expect(validateInt("-10", 0, 100)).toBe(false);
      });
    });

    describe("validateFloat", () => {
      test("should validate floats", () => {
        expect(validateFloat("3.14")).toBe(true);
        expect(validateFloat("0.5")).toBe(true);
        expect(validateFloat("-2.5")).toBe(true);
      });

      test("should validate integers as floats", () => {
        expect(validateFloat("42")).toBe(true);
      });

      test("should validate scientific notation", () => {
        expect(validateFloat("1e10")).toBe(true);
        expect(validateFloat("1.5e-3")).toBe(true);
      });

      test("should reject non-numbers", () => {
        expect(validateFloat("abc")).toBe(false);
        expect(validateFloat("")).toBe(false);
      });
    });

    describe("validateBool", () => {
      test("should validate true values", () => {
        expect(validateBool("true")).toBe(true);
        expect(validateBool("yes")).toBe(true);
        expect(validateBool("1")).toBe(true);
        expect(validateBool("on")).toBe(true);
      });

      test("should validate false values", () => {
        expect(validateBool("false")).toBe(true);
        expect(validateBool("no")).toBe(true);
        expect(validateBool("0")).toBe(true);
        expect(validateBool("off")).toBe(true);
      });

      test("should reject invalid values", () => {
        expect(validateBool("maybe")).toBe(false);
        expect(validateBool("")).toBe(false);
      });
    });

    describe("validateUuid", () => {
      test("should validate UUID v4", () => {
        expect(validateUuid("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
      });

      test("should be case insensitive", () => {
        expect(validateUuid("550E8400-E29B-41D4-A716-446655440000")).toBe(true);
      });

      test("should reject invalid UUIDs", () => {
        expect(validateUuid("not-a-uuid")).toBe(false);
        expect(validateUuid("550e8400-e29b-41d4-a716")).toBe(false);
        expect(validateUuid("")).toBe(false);
      });
    });

    describe("validateHex", () => {
      test("should validate hex strings", () => {
        expect(validateHex("deadbeef")).toBe(true);
        expect(validateHex("0123456789abcdef")).toBe(true);
        expect(validateHex("ABCDEF")).toBe(true);
      });

      test("should validate with length constraint", () => {
        expect(validateHex("deadbeef", 8)).toBe(true);
        expect(validateHex("dead", 8)).toBe(false);
      });

      test("should reject invalid hex", () => {
        expect(validateHex("xyz")).toBe(false);
        expect(validateHex("")).toBe(false);
      });
    });
  });

  describe("Format Validation", () => {
    describe("validateEmail", () => {
      test("should validate valid emails", () => {
        expect(validateEmail("user@example.com")).toBe(true);
        expect(validateEmail("user.name@example.co.uk")).toBe(true);
        expect(validateEmail("user+tag@example.com")).toBe(true);
      }, 10_000);

      test("should reject invalid emails", () => {
        expect(validateEmail("invalid")).toBe(false);
        expect(validateEmail("@example.com")).toBe(false);
        expect(validateEmail("user@")).toBe(false);
        expect(validateEmail("")).toBe(false);
      }, 10_000);
    });

    describe("validateUrl", () => {
      test("should validate HTTP URLs", () => {
        expect(validateUrl("http://example.com")).toBe(true);
        expect(validateUrl("https://example.com")).toBe(true);
        expect(validateUrl("https://example.com/path")).toBe(true);
        expect(validateUrl("https://example.com:8080")).toBe(true);
      }, 10_000);

      test("should reject invalid URLs", () => {
        expect(validateUrl("not-a-url")).toBe(false);
        expect(validateUrl("ftp://files.com")).toBe(false);
        expect(validateUrl("")).toBe(false);
      }, 10_000);

      test("should support custom schemes", () => {
        expect(validateUrl("ftp://files.com", "ftp,http")).toBe(true);
      });
    });

    describe("validateDomain", () => {
      test("should validate domains", () => {
        expect(validateDomain("example.com")).toBe(true);
        expect(validateDomain("sub.example.co.uk")).toBe(true);
      });

      test("should reject invalid domains", () => {
        expect(validateDomain("localhost")).toBe(false);
        expect(validateDomain("-example.com")).toBe(false);
        expect(validateDomain("")).toBe(false);
      });
    });

    describe("validateIpv4", () => {
      test("should validate IPv4 addresses", () => {
        expect(validateIpv4("192.168.1.1")).toBe(true);
        expect(validateIpv4("0.0.0.0")).toBe(true);
        expect(validateIpv4("255.255.255.255")).toBe(true);
      });

      test("should reject invalid IPv4", () => {
        expect(validateIpv4("256.1.1.1")).toBe(false);
        expect(validateIpv4("192.168.1")).toBe(false);
        expect(validateIpv4("")).toBe(false);
      });
    });

    describe("validateIpv6", () => {
      test("should validate IPv6 addresses", () => {
        expect(validateIpv6("::1")).toBe(true);
        expect(validateIpv6("2001:db8::1")).toBe(true);
      });

      test("should reject invalid IPv6", () => {
        expect(validateIpv6("not-ipv6")).toBe(false);
        expect(validateIpv6("")).toBe(false);
      });
    });

    describe("validateDate", () => {
      test("should validate dates", () => {
        expect(validateDate("2024-01-15")).toBe(true);
        expect(validateDate("2024-12-31")).toBe(true);
      });

      test("should reject invalid dates", () => {
        expect(validateDate("2024-02-30")).toBe(false);
        expect(validateDate("2024-13-01")).toBe(false);
        expect(validateDate("not-a-date")).toBe(false);
      });
    });

    describe("validateTime", () => {
      test("should validate times", () => {
        expect(validateTime("12:30:00")).toBe(true);
        expect(validateTime("00:00:00")).toBe(true);
        expect(validateTime("23:59:59")).toBe(true);
      });

      test("should reject invalid times", () => {
        expect(validateTime("25:00:00")).toBe(false);
        expect(validateTime("12:60:00")).toBe(false);
        expect(validateTime("not-a-time")).toBe(false);
      });
    });

    describe("validateSemver", () => {
      test("should validate semver", () => {
        expect(validateSemver("1.2.3")).toBe(true);
        expect(validateSemver("v1.2.3")).toBe(true);
        expect(validateSemver("1.0.0-beta")).toBe(true);
        expect(validateSemver("1.0.0+build")).toBe(true);
      }, 10_000);

      test("should reject invalid semver", () => {
        expect(validateSemver("1.2")).toBe(false);
        expect(validateSemver("1")).toBe(false);
        expect(validateSemver("not-semver")).toBe(false);
      }, 10_000);
    });
  });

  describe("Path Validation", () => {
    describe("validateFilename", () => {
      test("should validate safe filenames", () => {
        expect(validateFilename("file.txt")).toBe(true);
        expect(validateFilename("my-file.tar.gz")).toBe(true);
      });

      test("should reject unsafe filenames", () => {
        expect(validateFilename("../etc/passwd")).toBe(false);
        expect(validateFilename("/etc/passwd")).toBe(false);
        expect(validateFilename("-file.txt")).toBe(false);
      });
    });

    describe("validatePathChars", () => {
      test("should validate safe paths", () => {
        expect(validatePathChars("/home/user/file.txt")).toBe(true);
        expect(validatePathChars("./relative/path")).toBe(true);
      });

      test("should reject unsafe chars", () => {
        expect(validatePathChars("/path;rm -rf /")).toBe(false);
        expect(validatePathChars("/path|cat")).toBe(false);
      });
    });
  });

  describe("Sanitization", () => {
    describe("sanitizeHtml", () => {
      test("should escape HTML entities", () => {
        const result = sanitizeHtml("<script>alert('xss')</script>");
        expect(result).not.toContain("<script>");
        expect(result).toContain("&lt;");
        expect(result).toContain("&gt;");
      });

      test("should escape quotes", () => {
        const result = sanitizeHtml('test "quoted" value');
        expect(result).toContain("&quot;");
      });

      test("should escape ampersands", () => {
        const result = sanitizeHtml("a & b");
        expect(result).toContain("&amp;");
      });

      test("should handle empty string", () => {
        expect(sanitizeHtml("")).toBe("");
      });
    });

    describe("sanitizeSql", () => {
      test("should escape single quotes", () => {
        const result = sanitizeSql("O'Brien");
        expect(result).toContain("''");
      });

      test("should handle empty string", () => {
        expect(sanitizeSql("")).toBe("");
      });
    });

    describe("sanitizeFilename", () => {
      test("should remove path separators", () => {
        const result = sanitizeFilename("my/file.txt");
        expect(result).not.toContain("/");
      });

      test("should remove shell metacharacters", () => {
        const result = sanitizeFilename("file;rm -rf /");
        expect(result).not.toContain(";");
      });
    });

    describe("sanitizeJson", () => {
      test("should escape newlines", () => {
        const result = sanitizeJson("line1\nline2");
        expect(result).toContain("\\n");
      });
    });
  });

  describe("Complex Validation", () => {
    describe("validateRegex", () => {
      test("should match patterns", () => {
        expect(validateRegex("abc123", "^[a-z0-9]+$")).toBe(true);
        expect(validateRegex("ABC", "^[a-z]+$")).toBe(false);
      });
    });

    describe("validateLength", () => {
      test("should validate length range", () => {
        expect(validateLength("hello", 1, 10)).toBe(true);
        expect(validateLength("hi", 5)).toBe(false);
        expect(validateLength("hello world", undefined, 5)).toBe(false);
      });
    });

    describe("validateEnum", () => {
      test("should validate against options", () => {
        expect(validateEnum("red", ["red", "green", "blue"])).toBe(true);
        expect(validateEnum("yellow", ["red", "green", "blue"])).toBe(false);
      });
    });
  });

  describe("Convenience Validators", () => {
    test("validators.email should return validation result", () => {
      const valid = validators.email("test@example.com");
      expect(valid.valid).toBe(true);
      expect(valid.error).toBeUndefined();

      const invalid = validators.email("invalid");
      expect(invalid.valid).toBe(false);
      expect(invalid.error).toBeDefined();
    }, 10_000);

    test("validators.url should return validation result", () => {
      const valid = validators.url("https://example.com");
      expect(valid.valid).toBe(true);

      const invalid = validators.url("not-a-url");
      expect(invalid.valid).toBe(false);
    }, 10_000);

    test("validators.uuid should return validation result", () => {
      const valid = validators.uuid("550e8400-e29b-41d4-a716-446655440000");
      expect(valid.valid).toBe(true);

      const invalid = validators.uuid("not-uuid");
      expect(invalid.valid).toBe(false);
    });
  });
});

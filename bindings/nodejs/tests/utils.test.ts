/**
 * MAINFRAME Node.js Bindings - Utils Module Tests
 */

import {
  cleanupDurableStateForTestFile,
  prepareDurableStateForTestFile,
  resetDurableControlPlaneStateForTest,
} from "./setup";

import {
  describe,
  test,
  expect,
  afterAll,
  beforeAll,
  beforeEach,
  setDefaultTimeout,
} from "bun:test";
import { setConfig } from "../src/core";
import {
  // UUID and Random
  uuid,
  randomString,
  randomHex,
  randomRange,
  randomToken,

  // Timestamps
  now,
  nowIso,
  nowMs,
  timestamp,
  epoch,

  // Hashing
  md5,
  sha1,
  sha256,

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
  currentUser,
  getHostname,
  getOs,

  // Formatting
  formatBytes,
  formatDuration,
  formatNumber,
} from "../src/utils";

// Utility wrappers execute reviewed Mainframe contracts in child processes;
// keep a bounded budget that tolerates loaded hosted runners.
setDefaultTimeout(30_000);
beforeAll(prepareDurableStateForTestFile);
beforeEach(resetDurableControlPlaneStateForTest);
afterAll(cleanupDurableStateForTestFile);

describe("Utils Module", () => {
  beforeAll(() => {
    setConfig({ outputMode: "raw" });
  });

  describe("UUID and Random", () => {
    describe("uuid", () => {
      test("should generate valid UUID", () => {
        const id = uuid();
        expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
      });

      test("should generate unique UUIDs", () => {
        const id1 = uuid();
        const id2 = uuid();
        expect(id1).not.toBe(id2);
      });
    });

    describe("randomString", () => {
      test("should generate string of specified length", () => {
        const str = randomString(16);
        expect(str.length).toBe(16);
      });

      test("should generate alphanumeric characters", () => {
        const str = randomString(100);
        expect(str).toMatch(/^[a-zA-Z0-9]+$/);
      });

      test("should generate unique strings", () => {
        const str1 = randomString(16);
        const str2 = randomString(16);
        expect(str1).not.toBe(str2);
      });
    });

    describe("randomHex", () => {
      test("should generate hex string of specified length", () => {
        const hex = randomHex(8);
        expect(hex.length).toBe(8);
      });

      test("should generate valid hex characters", () => {
        const hex = randomHex(32);
        expect(hex).toMatch(/^[0-9a-f]+$/i);
      });
    });

    describe("randomRange", () => {
      test("should generate number in range", () => {
        for (let i = 0; i < 20; i++) {
          const num = randomRange(1, 10);
          expect(num).toBeGreaterThanOrEqual(1);
          expect(num).toBeLessThanOrEqual(10);
        }
      }, 15_000);
    });

    describe("randomToken", () => {
      test("should generate URL-safe token", () => {
        const token = randomToken(32);
        expect(token.length).toBe(32);
        expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
      });
    });
  });

  describe("Timestamps", () => {
    describe("now", () => {
      test("should return current Unix timestamp", () => {
        const ts = now();
        const jsTs = Math.floor(Date.now() / 1000);
        // Allow 2 second tolerance
        expect(Math.abs(ts - jsTs)).toBeLessThan(2);
      });

      test("should return number", () => {
        expect(typeof now()).toBe("number");
      });
    });

    describe("nowIso", () => {
      test("should return ISO 8601 format", () => {
        const iso = nowIso();
        expect(iso).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
      });
    });

    describe("nowMs", () => {
      test("should return milliseconds", () => {
        const ms = nowMs();
        expect(ms).toBeGreaterThan(1000000000000);
      });
    });

    describe("timestamp", () => {
      test("should return formatted timestamp", () => {
        const ts = timestamp();
        expect(ts).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
      });
    });

    describe("epoch", () => {
      test("should return Unix epoch", () => {
        const e = epoch();
        expect(typeof e).toBe("number");
        expect(e).toBeGreaterThan(0);
      });
    });
  });

  describe("Hashing", () => {
    describe("md5", () => {
      test("should generate MD5 hash", () => {
        const hash = md5("hello world");
        expect(hash).toBe("5eb63bbbe01eeed093cb22bb8f5acdc3");
      });

      test("should generate 32 character hex string", () => {
        const hash = md5("test");
        expect(hash.length).toBe(32);
        expect(hash).toMatch(/^[0-9a-f]+$/);
      });
    });

    describe("sha1", () => {
      test("should generate SHA-1 hash", () => {
        const hash = sha1("hello world");
        expect(hash).toBe("2aae6c35c94fcfb415dbe95f408b9ce91ee846ed");
      });

      test("should generate 40 character hex string", () => {
        const hash = sha1("test");
        expect(hash.length).toBe(40);
      });
    });

    describe("sha256", () => {
      test("should generate SHA-256 hash", () => {
        const hash = sha256("hello world");
        expect(hash).toBe("b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9");
      });

      test("should generate 64 character hex string", () => {
        const hash = sha256("test");
        expect(hash.length).toBe(64);
      });
    });
  });

  describe("Encoding", () => {
    describe("base64Encode/base64Decode", () => {
      test("should encode and decode", () => {
        const original = "hello world";
        const encoded = base64Encode(original);
        expect(encoded).toBe("aGVsbG8gd29ybGQ=");

        const decoded = base64Decode(encoded);
        expect(decoded).toBe(original);
      });

      test("should handle empty string", () => {
        expect(base64Encode("")).toBe("");
      });
    });

    describe("hexEncode/hexDecode", () => {
      test("should encode and decode", () => {
        const original = "hello";
        const encoded = hexEncode(original);
        expect(encoded).toBe("68656c6c6f");

        const decoded = hexDecode(encoded);
        expect(decoded).toBe(original);
      });
    });

    describe("urlEncode/urlDecode", () => {
      test("should encode spaces", () => {
        const encoded = urlEncode("hello world");
        expect(encoded).toContain("%20");
      });

      test("should decode back", () => {
        const encoded = urlEncode("hello world");
        const decoded = urlDecode(encoded);
        expect(decoded).toBe("hello world");
      });

      test("should handle special characters", () => {
        const encoded = urlEncode("a=b&c=d");
        expect(encoded).toContain("%");
      });
    });
  });

  describe("String Utilities", () => {
    describe("trimString", () => {
      test("should trim whitespace", () => {
        expect(trimString("  hello  ")).toBe("hello");
        expect(trimString("\thello\n")).toBe("hello");
      });
    });

    describe("toLower", () => {
      test("should convert to lowercase", () => {
        expect(toLower("HELLO")).toBe("hello");
        expect(toLower("Hello World")).toBe("hello world");
      });
    });

    describe("toUpper", () => {
      test("should convert to uppercase", () => {
        expect(toUpper("hello")).toBe("HELLO");
        expect(toUpper("Hello World")).toBe("HELLO WORLD");
      });
    });

    describe("capitalize", () => {
      test("should capitalize first letter", () => {
        expect(capitalize("hello")).toBe("Hello");
      });
    });

    describe("contains", () => {
      test("should detect substring", () => {
        expect(contains("hello world", "world")).toBe(true);
        expect(contains("hello world", "foo")).toBe(false);
      });
    });

    describe("startsWith", () => {
      test("should detect prefix", () => {
        expect(startsWith("hello world", "hello")).toBe(true);
        expect(startsWith("hello world", "world")).toBe(false);
      });
    });

    describe("endsWith", () => {
      test("should detect suffix", () => {
        expect(endsWith("hello world", "world")).toBe(true);
        expect(endsWith("hello world", "hello")).toBe(false);
      });
    });
  });

  describe("System Utilities", () => {
    describe("commandExists", () => {
      test("should detect existing commands", () => {
        expect(commandExists("bash")).toBe(true);
        expect(commandExists("ls")).toBe(true);
      });

      test("should return false for non-existent commands", () => {
        expect(commandExists("nonexistent_command_xyz_123")).toBe(false);
      });
    });

    describe("currentUser", () => {
      test("should return username", () => {
        const user = currentUser();
        expect(typeof user).toBe("string");
        expect(user.length).toBeGreaterThan(0);
      });
    });

    describe("getHostname", () => {
      test("should return hostname", () => {
        const hostname = getHostname();
        expect(typeof hostname).toBe("string");
        expect(hostname.length).toBeGreaterThan(0);
      });
    });

    describe("getOs", () => {
      test("should return OS name", () => {
        const os = getOs();
        expect(["linux", "darwin", "windows"].some((s) => os.includes(s))).toBe(true);
      });
    });
  });

  describe("Formatting", () => {
    describe("formatBytes", () => {
      test("should format bytes", () => {
        expect(formatBytes(1024)).toContain("K");
        expect(formatBytes(1048576)).toContain("M");
      });
    });

    describe("formatDuration", () => {
      test("should format seconds", () => {
        const result = formatDuration(3661);
        expect(result).toContain("h");
        expect(result).toContain("m");
        expect(result).toContain("s");
      });
    });

    describe("formatNumber", () => {
      test("should add thousands separator", () => {
        const result = formatNumber(1234567);
        expect(result).toBe("1,234,567");
        expect(formatNumber(-1234567)).toBe("-1,234,567");
      });
    });
  });
});

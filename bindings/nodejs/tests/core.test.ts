/**
 * MAINFRAME Node.js Bindings - Core Module Tests
 */

import { describe, test, expect, beforeAll } from "bun:test";
import {
  detectMainframeRoot,
  verifyInstallation,
  getConfig,
  setConfig,
  execBash,
  callFunction,
  callFunctionRaw,
} from "../src/core";

describe("Core Module", () => {
  describe("detectMainframeRoot", () => {
    test("should detect MAINFRAME installation", () => {
      const root = detectMainframeRoot();
      expect(root).not.toBeNull();
      expect(typeof root).toBe("string");
    });

    test("should find lib/common.sh in detected root", async () => {
      const root = detectMainframeRoot();
      if (root) {
        const file = Bun.file(`${root}/lib/common.sh`);
        expect(await file.exists()).toBe(true);
      }
    });
  });

  describe("verifyInstallation", () => {
    test("should verify MAINFRAME is installed", () => {
      const result = verifyInstallation();
      expect(result.installed).toBe(true);
      expect(result.root).not.toBeNull();
    });

    test("should return version if available", () => {
      const result = verifyInstallation();
      if (result.installed) {
        // Version may or may not be set
        expect(typeof result.version === "string" || result.version === null).toBe(true);
      }
    });
  });

  describe("getConfig/setConfig", () => {
    test("should return default configuration", () => {
      const config = getConfig();
      expect(config).toHaveProperty("mainframeRoot");
      expect(config).toHaveProperty("outputMode");
      expect(config).toHaveProperty("timeout");
      expect(config).toHaveProperty("shell");
    });

    test("should update configuration", () => {
      const originalConfig = getConfig();
      setConfig({ timeout: 60000 });

      const newConfig = getConfig();
      expect(newConfig.timeout).toBe(60000);

      // Restore original
      setConfig({ timeout: originalConfig.timeout });
    });

    test("should preserve unmodified config values", () => {
      const originalConfig = getConfig();
      setConfig({ timeout: 45000 });

      const newConfig = getConfig();
      expect(newConfig.mainframeRoot).toBe(originalConfig.mainframeRoot);
      expect(newConfig.shell).toBe(originalConfig.shell);

      // Restore
      setConfig({ timeout: originalConfig.timeout });
    });
  });

  describe("execBash", () => {
    test("should execute simple bash commands", () => {
      const result = execBash('echo "hello"');
      expect(result.stdout.trim()).toBe("hello");
      expect(result.exitCode).toBe(0);
    });

    test("should capture stderr", () => {
      const result = execBash('echo "error" >&2');
      expect(result.stderr.trim()).toBe("error");
    });

    test("should return exit code on failure", () => {
      const result = execBash("exit 42");
      expect(result.exitCode).toBe(42);
    });

    test("should have MAINFRAME functions available", () => {
      const result = execBash("type json_object");
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("function");
    });
  });

  describe("callFunction", () => {
    beforeAll(() => {
      // Ensure raw mode for predictable output
      setConfig({ outputMode: "raw" });
    });

    test("should call MAINFRAME functions", () => {
      const result = callFunction<string>("json_object", ["name=test"]);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toContain("name");
        expect(result.data).toContain("test");
      }
    });

    test("should handle function arguments with spaces", () => {
      const result = callFunction<string>("json_object", ["name=hello world"]);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data).toContain("hello world");
      }
    });

    test("should return error for non-existent functions", () => {
      const result = callFunction<string>("nonexistent_function_xyz", []);
      // Non-existent command returns empty output with error
      expect(result.raw).toBe("");
    });
  });

  describe("callFunctionRaw", () => {
    test("should return raw string output", () => {
      const result = callFunctionRaw("json_object", ["name=test"]);
      expect(typeof result).toBe("string");
      expect(result).toContain("test");
    });

    test("should handle empty output", () => {
      const result = callFunctionRaw("true", []);
      expect(typeof result).toBe("string");
    });
  });
});

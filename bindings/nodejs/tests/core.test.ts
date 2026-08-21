/**
 * MAINFRAME Node.js Bindings - Core Module Tests
 */

import "./setup";

import { describe, test, expect, beforeAll } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import {
  detectMainframeRoot,
  verifyInstallation,
  getConfig,
  setConfig,
  execBash,
  invokeCanonical,
  callFunction,
  callFunctionRaw,
  resolveBash,
  approvedBashLayout,
  FIXED_BASH_CANDIDATES,
} from "../src/core";

const DURABLE_CLOSURE_FILES = [
  "bin/mainframe",
  "lib/common.sh",
  "lib/durable_invoke.sh",
  "control_plane/mainframe-control-plane",
  "control_plane/mainframe_control_plane/__init__.py",
  "control_plane/mainframe_control_plane/cli.py",
  "control_plane/mainframe_control_plane/coding.py",
  "control_plane/mainframe_control_plane/contracts.py",
  "control_plane/mainframe_control_plane/durability.py",
  "control_plane/mainframe_control_plane/errors.py",
  "control_plane/mainframe_control_plane/executor.py",
  "control_plane/mainframe_control_plane/kernel.py",
  "control_plane/mainframe_control_plane/memory.py",
  "control_plane/mainframe_control_plane/transient.py",
  "control_plane/mainframe_control_plane/worker.py",
] as const;

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`;
}

function writeDurableClosureFixture(root: string): void {
  for (const relative of DURABLE_CLOSURE_FILES) {
    const path = join(root, relative);
    mkdirSync(dirname(path), { recursive: true });
    if (!existsSync(path)) writeFileSync(path, "# fixture\n");
    if (relative === "bin/mainframe" || relative === "control_plane/mainframe-control-plane") {
      chmodSync(path, 0o755);
    }
  }
}

function controlPlaneResponseFixture(
  envelope: Record<string, unknown>,
  inputJson = '{"value":"hello"}',
): Record<string, unknown> {
  const bytes = (field: "stdout_b64" | "stderr_b64") =>
    Buffer.from(String(envelope[field] ?? ""), "base64");
  const error = envelope.error === null ? Buffer.alloc(0) : Buffer.from(String(envelope.error), "utf8");
  const receipt = {
    schema_version: envelope.schema_version,
    ok: envelope.ok,
    status: envelope.status,
    canonical_id: envelope.canonical_id,
    name: envelope.name,
    owner: envelope.owner,
    exit_code: envelope.exit_code,
    timed_out: envelope.timed_out,
    output_exceeded: envelope.output_exceeded,
    duration_ms: envelope.duration_ms,
    audit_id: envelope.audit_id,
    stdout_bytes: bytes("stdout_b64").byteLength,
    stdout_sha256: createHash("sha256").update(bytes("stdout_b64")).digest("hex"),
    stderr_bytes: bytes("stderr_b64").byteLength,
    stderr_sha256: createHash("sha256").update(bytes("stderr_b64")).digest("hex"),
    error_bytes: error.byteLength,
    error_sha256: createHash("sha256").update(error).digest("hex"),
  };
  return {
    ok: true,
    command: "canonical-invoke",
    result: {
      schema_version: 1,
      status: "completed",
      client_correlation_id: "__CID__",
      run_id: "run-11111111111111111111111111111111",
      call_id: "call-22222222222222222222222222222222",
      decision_id: "decision-33333333333333333333333333333333",
      evidence_id: "evidence-44444444444444444444444444444444",
      input_digest: createHash("sha256").update(inputJson).digest("hex"),
      outcome: envelope.ok === true ? "succeeded" : (envelope.timed_out === true ? "timed_out" : "failed"),
      result_available: true,
      broker_receipt: receipt,
      broker_envelope: envelope,
    },
  };
}

function controlPlaneFixtureSource(
  envelope: Record<string, unknown>,
  checks = "",
): string {
  return controlPlaneRawFixtureSource(
    JSON.stringify(controlPlaneResponseFixture(envelope)),
    checks,
  );
}

function controlPlaneRawFixtureSource(serialized: string, checks = ""): string {
  const [before, after] = serialized.split("__CID__");
  if (after === undefined) throw new Error("control-plane fixture lacks CID placeholder");
  return `#!/bin/sh
${checks}
IFS= read -r payload
[ "$payload" = '{"value":"hello"}' ] || exit 70
printf '%s%s%s\\n' ${shellQuote(before)} "\${12}" ${shellQuote(after)}
`;
}

function fakeBashScript(version: string, marker?: string): string {
  const [major, minor] = version.split(".");
  return `#!/bin/sh
${marker ? `printf ran > ${JSON.stringify(marker)}\n` : ""}
if [ "$1" != "--noprofile" ] || [ "$2" != "--norc" ] || [ "$3" != "-p" ] || [ "$4" != "-c" ]; then
  exit 64
fi
printf '%s %s\\n' '${major}' '${minor}'
`;
}

function runCoreSnippet(
  source: string,
  env: Record<string, string> = {},
  cwd?: string,
): ReturnType<typeof spawnSync> {
  return spawnSync(process.execPath, ["-e", source], {
    encoding: "utf8",
    cwd,
    env: { ...process.env, ...env },
  });
}

function resolveWithFakeBash(version: string): {
  status: number | null;
  shell: string;
  stderr: string;
  fakeBash: string;
  canonicalShell: string;
} {
  const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-bash-"));
  const fakeBash = join(tempDir, "bash");
  writeFileSync(fakeBash, fakeBashScript(version));
  chmodSync(fakeBash, 0o755);

  try {
    const coreUrl = new URL("../src/core.ts", import.meta.url).href;
    const result = runCoreSnippet(
      `import { resolveBash } from ${JSON.stringify(coreUrl)}; console.log(resolveBash());`,
      { MAINFRAME_BASH: fakeBash },
    );

    return {
      status: result.status,
      shell: result.stdout.trim(),
      stderr: result.stderr,
      fakeBash,
      canonicalShell: realpathSync(fakeBash),
    };
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

function writeInvalidResultBrokerFixture(
  root: string,
  marker: string,
  result: Record<string, unknown>,
): void {
  const canonicalId = "mf:data:json:json_string";
  writeDurableClosureFixture(root);
  mkdirSync(join(root, "bin"), { recursive: true });
  writeFileSync(
    join(root, "MANIFEST.json"),
    JSON.stringify({
      manifest_version: 1,
      exports: {
        [canonicalId]: {
          name: "json_string",
          owner: "json",
          result,
          contract_status: "reviewed",
          profiles: ["stable-core"],
          effects: ["pure"],
          capabilities: [],
          input_schema: {
            type: "object",
            properties: { value: { type: "string" } },
            required: ["value"],
            additionalProperties: false,
          },
          call_shape: {
            kind: "argv",
            arguments: [{ field: "value", mode: "scalar" }],
          },
          timeout_ms: 5000,
          output_limit: 65536,
        },
      },
      name_index: { json_string: canonicalId },
    }),
  );
  const executable = join(root, "bin", "mainframe");
  writeFileSync(executable, `#!/bin/sh\nprintf ran > ${JSON.stringify(marker)}\n`);
  chmodSync(executable, 0o755);
}

function brokerEnvelopeFixture(overrides: Record<string, unknown>): Record<string, unknown> {
  return {
    schema_version: 1,
    ok: false,
    status: "function_error",
    canonical_id: "mf:data:json:json_string",
    name: "json_string",
    owner: "json",
    exit_code: 1,
    timed_out: false,
    output_exceeded: false,
    duration_ms: 0,
    audit_id: "inv-fixture",
    stdout_b64: "",
    stderr_b64: "",
    error: null,
    ...overrides,
  };
}

function nestedGroupBrokerSource(
  marker: string,
  ready?: string,
  outputOverflow = false,
): string {
  const overflow = outputOverflow
    ? `chunk=${JSON.stringify("x".repeat(4096))}\nfor ((i=0; i<900; i++)); do printf '%s' "$chunk"; done\n`
    : "";
  return `#!/bin/bash
set -m
nested_pid=
nested_pgid=
cleanup_started=0
cleanup() {
  if [ "$cleanup_started" -ne 0 ]; then return; fi
  cleanup_started=1
  trap - TERM INT HUP EXIT
  if [ -n "$nested_pgid" ]; then
    kill -TERM -- "-$nested_pgid" 2>/dev/null || true
    /bin/sleep 0.2
    kill -KILL -- "-$nested_pgid" 2>/dev/null || true
  fi
  if [ -n "$nested_pid" ]; then wait "$nested_pid" 2>/dev/null || true; fi
  exit 143
}
trap cleanup TERM INT HUP EXIT
(/bin/sleep 1.5; /usr/bin/touch ${JSON.stringify(marker)}) &
nested_pid=$!
nested_pgid=$(/bin/ps -o pgid= -p "$nested_pid" | /usr/bin/tr -d ' ')
${ready ? `/usr/bin/touch ${JSON.stringify(ready)}\n` : ""}${overflow}while :; do :; done
`;
}

describe("Core Module", () => {
  describe("resolveBash", () => {
    test("should reject an explicit Bash 4.3", () => {
      const result = resolveWithFakeBash("4.3");
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain("approved installation layout");
      expect(result.shell).toBe("");
    });

    test("should reject an unapproved temporary Bash even at 4.4", () => {
      const result = resolveWithFakeBash("4.4");
      expect(result.status).not.toBe(0);
      expect(result.stderr).toContain("approved installation layout");
      expect(result.shell).toBe("");
    });

    test("should fail closed for an explicit Bash 4.3", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-bash-"));
      const fakeBash = join(tempDir, "bash");
      writeFileSync(fakeBash, fakeBashScript("4.3"));
      chmodSync(fakeBash, 0o755);

      try {
        expect(() => resolveBash(fakeBash)).toThrow(
          "approved installation layout",
        );
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("import is lazy and does not probe MAINFRAME_BASH", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-lazy-import-"));
      const fakeBash = join(tempDir, "bash");
      const marker = join(tempDir, "import-probed");
      writeFileSync(fakeBash, fakeBashScript("5.2", marker));
      chmodSync(fakeBash, 0o755);

      try {
        const packageUrl = new URL("../src/index.ts", import.meta.url).href;
        const result = runCoreSnippet(
          `await import(${JSON.stringify(packageUrl)}); console.log("imported");`,
          { MAINFRAME_BASH: fakeBash },
        );
        expect(result.status).toBe(0);
        expect(result.stdout.trim()).toBe("imported");
        expect(existsSync(marker)).toBe(false);
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("rejects bare and relative overrides without executing them", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-relative-"));
      const fakeBash = join(tempDir, "marker-bash");
      const marker = join(tempDir, "relative-ran");
      writeFileSync(fakeBash, fakeBashScript("5.2", marker));
      chmodSync(fakeBash, 0o755);

      try {
        const coreUrl = new URL("../src/core.ts", import.meta.url).href;
        for (const override of ["marker-bash", "./marker-bash"]) {
          rmSync(marker, { force: true });
          const result = runCoreSnippet(
            `import { resolveBash } from ${JSON.stringify(coreUrl)}; console.log(resolveBash());`,
            {
              MAINFRAME_BASH: override,
              PATH: `${tempDir}:${process.env.PATH ?? ""}`,
            },
            tempDir,
          );
          expect(result.status).not.toBe(0);
          expect(result.stderr).toContain("absolute path");
          expect(existsSync(marker)).toBe(false);
        }
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("default resolution never executes a bash injected through PATH", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-path-"));
      const fakeBash = join(tempDir, "bash");
      const marker = join(tempDir, "path-ran");
      writeFileSync(fakeBash, fakeBashScript("5.2", marker));
      chmodSync(fakeBash, 0o755);

      try {
        const coreUrl = new URL("../src/core.ts", import.meta.url).href;
        const result = runCoreSnippet(
          `import { resolveBash } from ${JSON.stringify(coreUrl)}; console.log(resolveBash());`,
          {
            MAINFRAME_BASH: "",
            PATH: `${tempDir}:${process.env.PATH ?? ""}`,
          },
        );
        expect(result.status).toBe(0);
        expect(result.stdout.trim().startsWith("/")).toBe(true);
        expect(existsSync(marker)).toBe(false);
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    for (const [label, launcher, canonical] of [
      ["MacPorts", "/opt/local/bin/bash", "/opt/local/bin/bash"],
      [
        "Linuxbrew",
        "/home/linuxbrew/.linuxbrew/bin/bash",
        "/home/linuxbrew/.linuxbrew/Cellar/bash/5.2.37/bin/bash",
      ],
      [
        "Nix default profile",
        "/nix/var/nix/profiles/default/bin/bash",
        "/nix/store/abc123-bash-5.2p37/bin/bash",
      ],
      [
        "NixOS system profile",
        "/run/current-system/sw/bin/bash",
        "/nix/store/abc123-bash-5.2p37/bin/bash",
      ],
      [
        "Nix user profile",
        join(homedir(), ".nix-profile", "bin", "bash"),
        "/nix/store/abc123-bash-5.2p37/bin/bash",
      ],
    ] as const) {
      test(`automatic discovery includes an approved ${label} layout`, () => {
        expect(FIXED_BASH_CANDIDATES).toContain(launcher);
        expect(approvedBashLayout(canonical)).toBe(true);
      });
    }
  });

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

    test("should reject a managed launcher that lacks the durable closure", () => {
      const originalRoot = process.env.MAINFRAME_ROOT;
      const launcher = join(homedir(), ".local", "bin", "mainframe");
      const managed = dirname(dirname(realpathSync(launcher)));
      const expected = realpathSync(join(import.meta.dir, "../../.."));
      delete process.env.MAINFRAME_ROOT;
      try {
        expect(realpathSync(detectMainframeRoot() ?? "")).toBe(expected);
        expect(realpathSync(detectMainframeRoot() ?? "")).not.toBe(managed);
      } finally {
        if (originalRoot === undefined) delete process.env.MAINFRAME_ROOT;
        else process.env.MAINFRAME_ROOT = originalRoot;
      }
    });

    test("should fail closed for an explicitly configured invalid root", () => {
      const originalRoot = process.env.MAINFRAME_ROOT;
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-root-"));

      try {
        for (const invalidRoot of ["", join(tempDir, "missing")]) {
          process.env.MAINFRAME_ROOT = invalidRoot;
          expect(detectMainframeRoot()).toBeNull();
        }
      } finally {
        if (originalRoot === undefined) delete process.env.MAINFRAME_ROOT;
        else process.env.MAINFRAME_ROOT = originalRoot;
        rmSync(tempDir, { recursive: true, force: true });
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

    test("should reject a configured Bash 4.3 shell without mutating config", () => {
      const originalConfig = getConfig();
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-bash-config-"));
      const fakeBash = join(tempDir, "bash");
      writeFileSync(fakeBash, fakeBashScript("4.3"));
      chmodSync(fakeBash, 0o755);

      try {
        expect(() => setConfig({ shell: fakeBash })).toThrow(
          "approved installation layout",
        );
        expect(getConfig()).toEqual(originalConfig);
      } finally {
        setConfig({ shell: originalConfig.shell });
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("should reject a bare shell without PATH lookup or config mutation", () => {
      const originalConfig = getConfig();
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-config-relative-"));
      const marker = join(tempDir, "config-ran");
      const fakeBash = join(tempDir, "marker-bash");
      writeFileSync(fakeBash, fakeBashScript("5.2", marker));
      chmodSync(fakeBash, 0o755);
      const originalPath = process.env.PATH;
      process.env.PATH = `${tempDir}:${originalPath ?? ""}`;

      try {
        expect(() => setConfig({ shell: "marker-bash" })).toThrow("absolute path");
        expect(getConfig()).toEqual(originalConfig);
        expect(existsSync(marker)).toBe(false);
      } finally {
        process.env.PATH = originalPath;
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("should store and execute a canonical shell despite a per-call PATH swap", () => {
      const originalConfig = getConfig();
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-canonical-"));
      const alias = join(tempDir, "trusted-bash-alias");
      const marker = join(tempDir, "path-swap-ran");
      const fakePathBash = join(tempDir, "bash");
      symlinkSync(originalConfig.shell, alias);
      writeFileSync(fakePathBash, fakeBashScript("5.2", marker));
      chmodSync(fakePathBash, 0o755);

      try {
        setConfig({ shell: alias });
        expect(getConfig().shell).toBe(realpathSync(originalConfig.shell));

        const result = execBash('printf "%s" "canonical-safe"', {
          env: { PATH: `${tempDir}:${process.env.PATH ?? ""}` },
        });
        expect(result.exitCode).toBe(0);
        expect(result.stdout).toBe("canonical-safe");
        expect(existsSync(marker)).toBe(false);
      } finally {
        setConfig({ shell: originalConfig.shell });
        rmSync(tempDir, { recursive: true, force: true });
      }
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

    test("should ignore a poisoned BASH_ENV startup hook", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-bash-env-"));
      const poison = join(tempDir, "poison-bash-env.sh");
      const marker = join(tempDir, "bash-env-ran");
      writeFileSync(
        poison,
        'printf poisoned > "$MAINFRAME_BASH_ENV_MARKER"\nexit 97\n',
      );

      try {
        const result = execBash('printf "%s" "binding-safe"', {
          env: {
            BASH_ENV: poison,
            MAINFRAME_BASH_ENV_MARKER: marker,
          },
        });

        expect(result.exitCode).toBe(0);
        expect(result.stdout).toBe("binding-safe");
        expect(existsSync(marker)).toBe(false);
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    for (const [variable, value] of [
      ["BASH_ENV", "/tmp/mainframe-should-not-load"],
      ["LD_PRELOAD", "/tmp/mainframe-should-not-load.so"],
      ["DYLD_INSERT_LIBRARIES", "/tmp/mainframe-should-not-load.dylib"],
      ["BASH_FUNC_mainframe_poison%%", "() { :; }"],
      ["RUBYOPT", "-r/tmp/mainframe-should-not-load.rb"],
      ["RUBYLIB", "/tmp/mainframe-should-not-load"],
    ] as const) {
      test(`should strip passive code-loader variable ${variable}`, () => {
        const result = execBash(`printenv '${variable}'`, {
          env: { [variable]: value },
        });

        expect(result.exitCode).toBe(1);
        expect(result.stdout).toBe("");
      });
    }
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

    test("should map an exit-kind result to status with no stdout payload", () => {
      const result = callFunction<string>("validate_email", ["test@example.com"]);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe("");
      expect(result.raw).toBe("");
    });

    test("should return error for non-existent functions", () => {
      const result = callFunction<string>("nonexistent_function_xyz", []);
      expect(result.success).toBe(false);
      expect(result.raw).toBe("");
      if (!result.success) {
        expect(result.error).toContain("not broker-invocable");
      }
    });

    for (const name of ["id", "printf", "printenv"]) {
      test(`should fail closed for external executable ${name}`, () => {
        const result = callFunction<string>(name, []);
        expect(result.success).toBe(false);
        expect(result.raw).toBe("");
        if (!result.success) {
          expect(result.error).toContain("not broker-invocable");
        }
      });
    }

    for (const name of [
      "array_count", "array_filter", "array_first", "array_get",
      "array_intersect", "array_last", "array_length", "array_reverse",
      "array_slice", "array_sum", "array_unique", "collection_count",
      "collection_filter", "collection_first", "collection_intersect",
      "collection_last", "collection_length", "collection_reverse",
      "collection_slice", "collection_sum", "collection_unique",
      "safe_array_get",
      "awm_compress", "awm_handoff_prepare", "awm_handoff_accept",
      "awm_stream_compress", "awm_protocol_handoff_prepare",
      "awm_protocol_handoff_accept",
    ]) {
      test(`should fail closed for unreviewed call shape ${name}`, () => {
        const result = callFunction<string>(name, ["ignored"]);
        expect(result.success).toBe(false);
        expect(result.raw).toBe("");
        if (!result.success) {
          expect([
            `MAINFRAME function is not reviewed for stable-core: ${name}`,
            `MAINFRAME function is not broker-invocable: ${name}`,
          ]).toContain(result.error);
        }
      });
    }

    test("should reject an ambient executable before PATH lookup", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-external-"));
      const marker = join(tempDir, "external-ran");
      const fakeId = join(tempDir, "id");
      writeFileSync(fakeId, `#!/bin/sh\nprintf ran > ${JSON.stringify(marker)}\n`);
      chmodSync(fakeId, 0o755);
      const originalPath = process.env.PATH;
      process.env.PATH = `${tempDir}:${originalPath ?? ""}`;

      try {
        const result = callFunction<string>("id", []);
        expect(result.success).toBe(false);
        expect(existsSync(marker)).toBe(false);
      } finally {
        process.env.PATH = originalPath;
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("should reject shell syntax in function names", () => {
      const result = callFunction<string>("printf; echo injected", []);
      expect(result.success).toBe(false);
      expect(result.raw).toBe("");
      if (!result.success) {
        expect(result.error).toContain("Invalid MAINFRAME function name");
      }
    });
  });

  describe("callFunctionRaw", () => {
    test("should return raw string output", () => {
      const result = callFunctionRaw("json_object", ["name=test"]);
      expect(typeof result).toBe("string");
      expect(result).toContain("test");
    });

    test("should handle empty output", () => {
      const result = callFunctionRaw("id", []);
      expect(result).toBe("");
    });

    test("should preserve exact leading and trailing whitespace from stdout", () => {
      expect(callFunctionRaw("trim_right", ["  keep  "])).toBe("  keep\n");
      expect(callFunctionRaw("trim_left", ["  keep  "])).toBe("keep  \n");
    }, 10_000);
  });

  describe("invokeCanonical", () => {
    test("managed launcher wins over stale legacy root for real broker calls", () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-managed-call-"));
      const home = join(tempDir, "home");
      const managedRoot = join(tempDir, "managed-candidate");
      const legacyRoot = join(home, ".mainframe");
      const staleMarker = join(tempDir, "stale-broker-ran");
      const unusedMarker = join(tempDir, "managed-broker-ran");
      const canonicalId = "mf:data:json:json_string";

      try {
        for (const root of [managedRoot, legacyRoot]) {
          writeInvalidResultBrokerFixture(root, unusedMarker, { kind: "stdout" });
          mkdirSync(join(root, "lib"), { recursive: true });
          writeFileSync(join(root, "lib", "common.sh"), "# fixture\n");
        }

        const envelope = brokerEnvelopeFixture({
          ok: true,
          status: "success",
          exit_code: 0,
          stdout_b64: Buffer.from("managed", "utf8").toString("base64"),
        });
        writeFileSync(
          join(managedRoot, "bin", "mainframe"),
          controlPlaneFixtureSource(envelope),
        );
        chmodSync(join(managedRoot, "bin", "mainframe"), 0o755);
        writeFileSync(
          join(legacyRoot, "bin", "mainframe"),
          `#!/bin/sh\nprintf ran > ${JSON.stringify(staleMarker)}\nexit 97\n`,
        );
        chmodSync(join(legacyRoot, "bin", "mainframe"), 0o755);

        mkdirSync(join(home, ".local", "bin"), { recursive: true });
        symlinkSync(
          join(managedRoot, "bin", "mainframe"),
          join(home, ".local", "bin", "mainframe"),
        );

        const coreUrl = new URL("../src/core.ts", import.meta.url).href;
        const childEnvironment = { ...process.env, HOME: home };
        delete childEnvironment.MAINFRAME_ROOT;
        const result = spawnSync(
          process.execPath,
          [
            "-e",
            `import { invokeCanonical, callFunction } from ${JSON.stringify(coreUrl)};
const invocation = invokeCanonical(${JSON.stringify(canonicalId)}, { value: "hello" });
const byName = callFunction("json_string", ["hello"]);
if (!byName.success) throw new Error(byName.error);
console.log(JSON.stringify({ canonical: invocation.stdout, byName: byName.data }));`,
          ],
          { encoding: "utf8", env: childEnvironment },
        );

        expect(result.status).toBe(0);
        expect(result.stderr).toBe("");
        expect(JSON.parse(result.stdout)).toEqual({
          canonical: "managed",
          byName: "managed",
        });
        expect(existsSync(staleMarker)).toBe(false);
      } finally {
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    test("should expose strict broker identity and decoded output", () => {
      const stateDir = realpathSync(mkdtempSync(join(tmpdir(), "mainframe-node-audit-")));
      chmodSync(stateDir, 0o700);
      let result: ReturnType<typeof invokeCanonical> | null = null;
      try {
        result = invokeCanonical(
          "mf:data:json:json_object",
          { pairs: ["name=John"] },
          { env: { XDG_STATE_HOME: stateDir } },
        );
      } finally {
        rmSync(stateDir, { recursive: true, force: true });
      }
      if (result === null) throw new Error("broker result was not produced");

      expect(result.envelope?.schema_version).toBe(1);
      expect(result.envelope?.ok).toBe(true);
      expect(result.envelope?.status).toBe("success");
      expect(result.envelope?.canonical_id).toBe("mf:data:json:json_object");
      expect(result.envelope?.name).toBe("json_object");
      expect(result.envelope?.owner).toBe("json");
      expect(result.envelope?.exit_code).toBe(0);
      expect(result.envelope?.audit_id.startsWith("inv-")).toBe(true);
      expect(result.controlPlane.status).toBe("completed");
      expect(result.controlPlane.outcome).toBe("succeeded");
      expect(result.controlPlane.resultAvailable).toBe(true);
      expect(result.controlPlane.clientCorrelationId).toMatch(/^client-nodejs-[0-9a-f]{32}$/);
      expect(result.controlPlane.runId).toMatch(/^run-[0-9a-f]{32}$/);
      expect(result.controlPlane.callId).toMatch(/^call-[0-9a-f]{32}$/);
      expect(result.controlPlane.decisionId).toMatch(/^decision-[0-9a-f]{32}$/);
      expect(result.controlPlane.evidenceId).toMatch(/^evidence-[0-9a-f]{32}$/);
      expect(result.controlPlane.inputDigest).toMatch(/^[0-9a-f]{64}$/);
      expect(result.controlPlane.brokerReceipt?.audit_id).toBe(result.envelope?.audit_id);
      expect(result.resultKind).toBe("stdout");
      expect(result.stdout).toBe('{"name":"John"}');
      expect(result.stderr).toBe("");
    });

    test("should reject undeclared canonical input before execution", () => {
      expect(() =>
        invokeCanonical("mf:data:json:json_string", {
          value: "ok",
          surprise: "not allowed",
        }),
      ).toThrow("undeclared field");
    });

    test("should bind schema defaults before computing the durable input digest", () => {
      const result = invokeCanonical("mf:std:validation:validate_int", { value: "42" });
      expect(result.envelope?.ok).toBe(true);
      expect(result.controlPlane.inputDigest).toBe(
        createHash("sha256").update('{"max":"","min":"","value":"42"}').digest("hex"),
      );
    });

    test("should pass the exact canonical argv and nodejs caller", () => {
      const originalConfig = getConfig();
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-argv-"));
      const marker = join(tempDir, "unused");
      writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
      const executable = join(tempDir, "bin", "mainframe");
      const envelope = brokerEnvelopeFixture({
        ok: true,
        status: "success",
        exit_code: 0,
      });
      writeFileSync(
        executable,
        controlPlaneFixtureSource(envelope, `[ "$#" -eq 12 ] &&
[ "$1" = invoke ] &&
[ "$2" = mf:data:json:json_string ] &&
[ "$3" = --input-json ] && [ "$4" = - ] &&
[ "$5" = --profile ] && [ "$6" = stable-core ] &&
[ "$7" = --format ] && [ "$8" = control-plane-json-v1 ] &&
[ "$9" = --caller ] && [ "\${10}" = nodejs ] &&
[ "\${11}" = --client-correlation-id ] &&
[ -n "\${12}" ] || exit 70`),
      );
      chmodSync(executable, 0o755);

      try {
        setConfig({ mainframeRoot: tempDir });
        const result = invokeCanonical("mf:data:json:json_string", { value: "hello" });
        expect(result.envelope?.ok).toBe(true);
        expect(result.controlPlane.clientCorrelationId).toMatch(/^client-nodejs-/);
      } finally {
        setConfig({ mainframeRoot: originalConfig.mainframeRoot });
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    for (const [label, invalidResult] of [
      ["unknown kind", { kind: "stream" }],
      ["extra field", { kind: "stdout", extra: true }],
    ] as const) {
      test(`should fail closed for malformed result contract: ${label}`, () => {
        const originalConfig = getConfig();
        const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-result-"));
        const marker = join(tempDir, "broker-ran");
        writeInvalidResultBrokerFixture(tempDir, marker, invalidResult);

        try {
          setConfig({ mainframeRoot: tempDir });
          expect(() =>
            invokeCanonical("mf:data:json:json_string", { value: "hello" }),
          ).toThrow("invalid result contract");
          expect(existsSync(marker)).toBe(false);
        } finally {
          setConfig({ mainframeRoot: originalConfig.mainframeRoot });
          rmSync(tempDir, { recursive: true, force: true });
        }
      });
    }

    for (const malformation of ["schema-extra", "argument-extra"] as const) {
      test(`should fail closed for malformed call contract: ${malformation}`, () => {
        const originalConfig = getConfig();
        const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-shape-"));
        const marker = join(tempDir, "broker-ran");
        writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
        const manifestPath = join(tempDir, "MANIFEST.json");
        const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
          exports: Record<
            string,
            {
              input_schema: Record<string, unknown>;
              call_shape: { arguments: Record<string, unknown>[] };
            }
          >;
        };
        const contract = manifest.exports["mf:data:json:json_string"];
        if (malformation === "schema-extra") {
          contract.input_schema.extra = true;
        } else {
          contract.call_shape.arguments[0].extra = true;
        }
        writeFileSync(manifestPath, JSON.stringify(manifest));

        try {
          setConfig({ mainframeRoot: tempDir });
          expect(() =>
            invokeCanonical("mf:data:json:json_string", { value: "hello" }),
          ).toThrow(/invalid input schema|invalid call argument/);
          expect(existsSync(marker)).toBe(false);
        } finally {
          setConfig({ mainframeRoot: originalConfig.mainframeRoot });
          rmSync(tempDir, { recursive: true, force: true });
        }
      });
    }

    test("should kill descendants when the broker leader exits first", async () => {
      const originalConfig = getConfig();
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-group-"));
      const marker = join(tempDir, "descendant-survived");
      writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
      const executable = join(tempDir, "bin", "mainframe");
      writeFileSync(
        executable,
        `#!/bin/sh\n(/bin/sleep 0.5; /usr/bin/touch ${JSON.stringify(marker)}) &\nexit 0\n`,
      );
      chmodSync(executable, 0o755);

      try {
        setConfig({ mainframeRoot: tempDir });
        expect(() =>
          invokeCanonical(
            "mf:data:json:json_string",
            { value: "hello" },
            { timeout: 100 },
          ),
        ).toThrow();
        await Bun.sleep(700);
        expect(existsSync(marker)).toBe(false);
      } finally {
        setConfig({ mainframeRoot: originalConfig.mainframeRoot });
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    for (const mode of ["timeout", "output overflow"] as const) {
      test(`should let the broker clean its nested group on ${mode}`, async () => {
        const originalConfig = getConfig();
        const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-nested-"));
        const marker = join(tempDir, "nested-survived");
        writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
        const executable = join(tempDir, "bin", "mainframe");
        writeFileSync(
          executable,
          nestedGroupBrokerSource(marker, undefined, mode === "output overflow"),
        );
        chmodSync(executable, 0o755);

        try {
          setConfig({ mainframeRoot: tempDir });
          expect(() =>
            invokeCanonical(
              "mf:data:json:json_string",
              { value: "hello" },
              { timeout: mode === "timeout" ? 100 : 5000 },
            ),
          ).toThrow();
          await Bun.sleep(1300);
          expect(existsSync(marker)).toBe(false);
        } finally {
          setConfig({ mainframeRoot: originalConfig.mainframeRoot });
          rmSync(tempDir, { recursive: true, force: true });
        }
      });
    }

    test("should clean the broker nested group when its parent is cancelled", async () => {
      const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-cancel-"));
      const marker = join(tempDir, "nested-survived");
      const ready = join(tempDir, "broker-ready");
      writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
      const executable = join(tempDir, "bin", "mainframe");
      writeFileSync(executable, nestedGroupBrokerSource(marker, ready));
      chmodSync(executable, 0o755);
      const coreUrl = new URL("../src/core.ts", import.meta.url).href;
      const caller = spawn(
        process.execPath,
        [
          "-e",
          `import { invokeCanonical } from ${JSON.stringify(coreUrl)};
invokeCanonical("mf:data:json:json_string", { value: "hello" }, { timeout: 5000 });`,
        ],
        {
          detached: true,
          env: { ...process.env, MAINFRAME_ROOT: tempDir },
          stdio: "ignore",
        },
      );

      try {
        const deadline = Date.now() + 3000;
        while (!existsSync(ready) && Date.now() < deadline) {
          await Bun.sleep(20);
        }
        expect(existsSync(ready)).toBe(true);
        process.kill(-caller.pid!, "SIGTERM");
        await Bun.sleep(1800);
        expect(existsSync(marker)).toBe(false);
      } finally {
        try {
          process.kill(-caller.pid!, "SIGKILL");
        } catch {
          // The cancelled process group normally no longer exists.
        }
        rmSync(tempDir, { recursive: true, force: true });
      }
    });

    for (const [label, envelope] of [
      ["unknown status", brokerEnvelopeFixture({ status: "mystery" })],
      ["failure with zero exit", brokerEnvelopeFixture({ exit_code: 0 })],
      [
        "timeout flag mismatch",
        brokerEnvelopeFixture({ status: "timeout", exit_code: 124 }),
      ],
      [
        "output flag mismatch",
        brokerEnvelopeFixture({ status: "output_limit", exit_code: 74 }),
      ],
    ] as const) {
      test(`should reject incoherent broker envelope: ${label}`, () => {
        const originalConfig = getConfig();
        const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-envelope-"));
        const marker = join(tempDir, "unused");
        writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
        const executable = join(tempDir, "bin", "mainframe");
        writeFileSync(
          executable,
          controlPlaneFixtureSource(envelope),
        );
        chmodSync(executable, 0o755);

        try {
          setConfig({ mainframeRoot: tempDir });
          expect(() =>
            invokeCanonical("mf:data:json:json_string", { value: "hello" }),
          ).toThrow("identity or semantic validation");
        } finally {
          setConfig({ mainframeRoot: originalConfig.mainframeRoot });
          rmSync(tempDir, { recursive: true, force: true });
        }
      });
    }

    for (const tamper of ["duplicate-key", "input-digest", "receipt-digest"] as const) {
      test(`should fail closed for control-plane ${tamper} tampering`, () => {
        const originalConfig = getConfig();
        const tempDir = mkdtempSync(join(tmpdir(), "mainframe-node-control-plane-"));
        const marker = join(tempDir, "unused");
        writeInvalidResultBrokerFixture(tempDir, marker, { kind: "stdout" });
        const envelope = brokerEnvelopeFixture({ ok: true, status: "success", exit_code: 0 });
        const response = controlPlaneResponseFixture(envelope) as {
          result: { input_digest: string; broker_receipt: { stdout_sha256: string } };
        };
        if (tamper === "input-digest") response.result.input_digest = "0".repeat(64);
        if (tamper === "receipt-digest") response.result.broker_receipt.stdout_sha256 = "0".repeat(64);
        let serialized = JSON.stringify(response);
        if (tamper === "duplicate-key") {
          serialized = serialized.replace('"ok":true', '"ok":true,"ok":true');
        }
        writeFileSync(
          join(tempDir, "bin", "mainframe"),
          controlPlaneRawFixtureSource(serialized),
        );
        chmodSync(join(tempDir, "bin", "mainframe"), 0o755);
        try {
          setConfig({ mainframeRoot: tempDir });
          expect(() => invokeCanonical("mf:data:json:json_string", { value: "hello" })).toThrow();
        } finally {
          setConfig({ mainframeRoot: originalConfig.mainframeRoot });
          rmSync(tempDir, { recursive: true, force: true });
        }
      });
    }
  });
});

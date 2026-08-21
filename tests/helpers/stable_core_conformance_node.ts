import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const SENTINEL = "@@MAINFRAME_CONFORMANCE@@";
const BROKER_ENVELOPE_KEYS = [
  "audit_id",
  "canonical_id",
  "duration_ms",
  "error",
  "exit_code",
  "name",
  "ok",
  "output_exceeded",
  "owner",
  "schema_version",
  "status",
  "stderr_b64",
  "stdout_b64",
  "timed_out",
];
const NODE_RESULT_KEYS = ["controlPlane", "envelope", "raw", "resultKind", "stderr", "stdout"];
const PI_DETAILS_KEYS = [
  "argumentMetadata",
  "broker",
  "canonicalId",
  "controlPlane",
  "functionName",
  "result",
  "risk",
  "root",
];
const CONTROL_PLANE_KEYS = [
  "brokerReceipt",
  "callId",
  "clientCorrelationId",
  "decisionId",
  "evidenceId",
  "inputDigest",
  "outcome",
  "resultAvailable",
  "runId",
  "schemaVersion",
  "status",
];
const PI_RESULT_KEYS = [
  "argumentCount",
  "code",
  "command",
  "signal",
  "stderr",
  "stdout",
  "timedOut",
];
const PI_BROKER_KEYS = [
  "auditId",
  "canonicalId",
  "durationMs",
  "error",
  "outputExceeded",
  "resultKind",
  "schemaVersion",
  "status",
];

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(2);
}

function exactKeys(value, keys) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).sort().join("\0") === [...keys].sort().join("\0")
  );
}

function encoded(value, label) {
  if (typeof value !== "string") {
    throw new TypeError(`${label} must be a string`);
  }
  return Buffer.from(value, "utf8").toString("base64");
}

function readCorpus(path) {
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  if (
    parsed === null ||
    typeof parsed !== "object" ||
    parsed.schema_version !== 1 ||
    !Array.isArray(parsed.cases)
  ) {
    fail(`unsupported conformance corpus: ${path}`);
  }
  return parsed;
}

function exceptionObservation(adapter, testCase, error) {
  return {
    adapter,
    case_id: testCase.case_id,
    exception: `${error instanceof Error ? error.name : "Error"}: ${
      error instanceof Error ? error.message : String(error)
    }`,
  };
}

async function runNode(sourceRoot, runtimeRoot, corpus, modulePath) {
  if (!existsSync(modulePath)) {
    fail(`current-run Node build is unavailable: ${modulePath}`);
  }
  const binding = await import(pathToFileURL(modulePath).href);
  if (typeof binding.setConfig !== "function" || typeof binding.invokeCanonical !== "function") {
    fail("built Node package does not export the canonical client surface");
  }
  binding.setConfig({ mainframeRoot: runtimeRoot, timeout: 35_000 });
  const observations = [];
  for (const testCase of corpus.cases) {
    try {
      const result = binding.invokeCanonical(testCase.canonical_id, testCase.input, {
        cwd: sourceRoot,
        timeout: 10_000,
      });
      if (!exactKeys(result, NODE_RESULT_KEYS)) {
        throw new TypeError("Node broker result shape is not exact");
      }
      if (!exactKeys(result.envelope, BROKER_ENVELOPE_KEYS)) {
        throw new TypeError("Node broker envelope shape is not exact");
      }
      if (!exactKeys(result.controlPlane, CONTROL_PLANE_KEYS)) {
        throw new TypeError("Node durable control-plane shape is not exact");
      }
      if (
        result.controlPlane.schemaVersion !== 1 ||
        result.controlPlane.status !== "completed" ||
        result.controlPlane.outcome !== "succeeded" ||
        result.controlPlane.resultAvailable !== true ||
        !/^client-nodejs-[0-9a-f]{32}$/.test(result.controlPlane.clientCorrelationId) ||
        !/^run-[0-9a-f]{32}$/.test(result.controlPlane.runId) ||
        !/^call-[0-9a-f]{32}$/.test(result.controlPlane.callId) ||
        !/^decision-[0-9a-f]{32}$/.test(result.controlPlane.decisionId) ||
        !/^evidence-[0-9a-f]{32}$/.test(result.controlPlane.evidenceId) ||
        !/^[0-9a-f]{64}$/.test(result.controlPlane.inputDigest)
      ) {
        throw new TypeError("Node durable control-plane identity is invalid");
      }
      if (typeof result.raw !== "string" || typeof result.resultKind !== "string") {
        throw new TypeError("Node broker result metadata has invalid types");
      }
      const stdoutB64 = encoded(result.stdout, "Node stdout");
      const stderrB64 = encoded(result.stderr, "Node stderr");
      if (
        stdoutB64 !== result.envelope.stdout_b64 ||
        stderrB64 !== result.envelope.stderr_b64
      ) {
        throw new TypeError("Node decoded output differs from its broker envelope");
      }
      observations.push({
        adapter: "node",
        case_id: testCase.case_id,
        schema_version: result.envelope.schema_version,
        ok: result.envelope.ok,
        status: result.envelope.status,
        canonical_id: result.envelope.canonical_id,
        name: result.envelope.name,
        owner: result.envelope.owner,
        result_kind: result.resultKind,
        exit_code: result.envelope.exit_code,
        timed_out: result.envelope.timed_out,
        output_exceeded: result.envelope.output_exceeded,
        duration_ms: result.envelope.duration_ms,
        audit_id: result.envelope.audit_id,
        stdout_b64: stdoutB64,
        stderr_b64: stderrB64,
        error: result.envelope.error,
      });
    } catch (error) {
      observations.push(exceptionObservation("node", testCase, error));
    }
  }
  return observations;
}

function findPiBinary(explicit) {
  const candidates = [
    explicit,
    process.env.MAINFRAME_PI_BIN,
    "/opt/homebrew/bin/pi",
    "/usr/local/bin/pi",
    "/home/linuxbrew/.linuxbrew/bin/pi",
    join(process.env.HOME || "", ".bun", "bin", "pi"),
  ];
  for (const candidate of candidates) {
    if (candidate && existsSync(candidate)) return candidate;
  }
  fail("Pi executable was not found at a reviewed location");
}

async function runPi(sourceRoot, runtimeRoot, corpus, explicitPi) {
  const piBin = findPiBinary(explicitPi);
  const piDist = dirname(realpathSync(piBin));
  const loaderPath = join(piDist, "core", "extensions", "loader.js");
  if (!existsSync(loaderPath)) fail(`Pi extension loader not found: ${loaderPath}`);
  const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
  const extensionPath = join(runtimeRoot, "skills", "pi", "extensions", "mainframe.ts");
  const loaded = await loadExtensions([extensionPath], runtimeRoot);
  if (loaded.errors.length || loaded.extensions.length !== 1) {
    fail(`Pi extension load failed: ${JSON.stringify(loaded.errors)}`);
  }
  const tool = loaded.extensions[0].tools.get("mainframe_exec")?.definition;
  if (!tool) fail("Pi mainframe_exec tool is unavailable");

  const observations = [];
  for (const testCase of corpus.cases) {
    try {
      const result = await tool.execute(
        `conformance-${testCase.case_id}`,
        {
          functionName: testCase.function_name,
          args: testCase.positional_args,
          root: runtimeRoot,
          cwd: sourceRoot,
          timeoutMs: 10_000,
        },
        undefined,
        undefined,
        { cwd: sourceRoot, ui: {} },
      );
      if (!exactKeys(result, ["content", "details"])) {
        throw new TypeError("Pi tool result shape is not exact");
      }
      if (
        !Array.isArray(result.content) ||
        result.content.length !== 1 ||
        !exactKeys(result.content[0], ["text", "type"]) ||
        result.content[0].type !== "text"
      ) {
        throw new TypeError("Pi tool content shape is not exact text");
      }
      if (!exactKeys(result.details, PI_DETAILS_KEYS)) {
        throw new TypeError(
          `Pi tool details shape is not exact: ${Object.keys(result.details ?? {}).sort().join(",")}`,
        );
      }
      if (!exactKeys(result.details.result, PI_RESULT_KEYS)) {
        throw new TypeError("Pi public result shape is not exact");
      }
      if (!exactKeys(result.details.broker, PI_BROKER_KEYS)) {
        throw new TypeError("Pi broker metadata shape is not exact");
      }
      if (!exactKeys(result.details.controlPlane, CONTROL_PLANE_KEYS)) {
        throw new TypeError("Pi durable control-plane shape is not exact");
      }
      if (
        result.details.controlPlane.schemaVersion !== 1 ||
        result.details.controlPlane.status !== "completed" ||
        result.details.controlPlane.outcome !== "succeeded" ||
        result.details.controlPlane.resultAvailable !== true ||
        !/^client-pi-[0-9a-f]{32}$/.test(result.details.controlPlane.clientCorrelationId) ||
        !/^run-[0-9a-f]{32}$/.test(result.details.controlPlane.runId) ||
        !/^call-[0-9a-f]{32}$/.test(result.details.controlPlane.callId) ||
        !/^decision-[0-9a-f]{32}$/.test(result.details.controlPlane.decisionId) ||
        !/^evidence-[0-9a-f]{32}$/.test(result.details.controlPlane.evidenceId) ||
        !/^[0-9a-f]{64}$/.test(result.details.controlPlane.inputDigest)
      ) {
        throw new TypeError("Pi durable control-plane identity is invalid");
      }
      encoded(result.content[0].text, "Pi content text");
      encoded(result.details.result.stdout, "Pi stdout");
      encoded(result.details.result.stderr, "Pi stderr");
      observations.push({
        adapter: "pi",
        case_id: testCase.case_id,
        content_text: result.content[0].text,
        details: result.details,
      });
    } catch (error) {
      observations.push(exceptionObservation("pi", testCase, error));
    }
  }
  return observations;
}

const [mode, sourceRoot, runtimeRoot, corpusPath, adapterArtifact] = process.argv.slice(2);
if (
  (mode !== "node" && mode !== "pi") ||
  !sourceRoot ||
  !runtimeRoot ||
  !corpusPath ||
  !adapterArtifact
) {
  fail(
    "usage: stable_core_conformance_node.ts <node|pi> " +
      "<source-root> <runtime-root> <corpus> <current-build|pi-bin>",
  );
}

const corpus = readCorpus(corpusPath);
const observations =
  mode === "node"
    ? await runNode(sourceRoot, runtimeRoot, corpus, adapterArtifact)
    : await runPi(sourceRoot, runtimeRoot, corpus, adapterArtifact);
process.stdout.write(`${SENTINEL}${JSON.stringify(observations)}\n`);

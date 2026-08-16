#!/usr/bin/env node
/**
 * Credentials-free Pi/AWM transition mechanism driver.
 *
 * This driver deliberately does not start an agent, load a provider adapter, or
 * contact a network service. It loads MAINFRAME's extension through the pinned
 * Pi runtime's real extension loader and invokes the registered mainframe_awm
 * tool directly. Its sole declared output is one canonical private JSON record
 * on stdout. The caller owns redaction, neutral-envelope construction, public
 * projection, containment, and the outer process timeout.
 */

import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
	closeSync,
	constants as fsConstants,
	existsSync,
	fstatSync,
	lstatSync,
	openSync,
	readFileSync,
	readSync,
	readdirSync,
	realpathSync,
} from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { homedir, platform } from "node:os";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const REQUEST_KIND = "mainframe-agent-impact-pi-awm-transition-request";
const RECORD_KIND = "mainframe-agent-impact-pi-awm-transition-private-record";
const CLAIM_SCOPE = "synthetic-treatment-investigate-awm-mechanism-conformance-only";
const PACKAGE_TREE_ALGORITHM = "mainframe-package-tree-sha256-v1";
const SNAPSHOT_TREE_ALGORITHM = "mainframe-agent-impact-private-tree-sha256-v1";
const PACKAGE_TREE_DOMAIN = Buffer.concat([
	Buffer.from("MAINFRAME-PACKAGE-TREE-SHA256-V1", "ascii"),
	Buffer.from([0]),
]);
const ZERO_SHA256 = "0".repeat(64);
const MAXIMUM_CONTEXT_BYTES = 8192;
const MAX_REQUEST_BYTES = 1024 * 1024;
const MAX_TREE_ENTRIES = 100_000;
const MAX_TREE_FILE_BYTES = 128 * 1024 * 1024;
const MAX_TREE_TOTAL_BYTES = 1024 * 1024 * 1024;
const MAX_CAPTURED_STDOUT_BYTES = 1024 * 1024;
const SAFE_PATH = "/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
const ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,127}$/;
const PAIR_PATTERN = /^pair-[0-9a-f]{16}$/;
const ARM_PATTERN = /^arm-[0-9a-f]{16}$/;
const NPM_PACKAGE_PATTERN = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]{0,127}$/;
const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/+:-]{0,255}$/;
const SESSION_PATTERN = /^[0-9a-f]{12}$/;
const HANDOFF_ID_PATTERN = /^handoff_[0-9]+_[A-Za-z0-9_-]+$/;

const TOP_LEVEL_KEYS = [
	"schema_version",
	"kind",
	"claim_scope",
	"binding",
	"paths",
	"runtime_expected",
	"budget",
	"fixture",
];
const BINDING_KEYS = [
	"preregistration_sha256",
	"randomization_context_sha256",
	"assignment_commitment_sha256",
	"study_id",
	"pair_id",
	"task_id",
	"replicate",
	"instance_sha256",
	"opaque_arm_id",
	"arm_mode",
	"phase",
];
const PATH_KEYS = [
	"mainframe_root",
	"pi_bin",
	"node_bin",
	"workspace",
	"awm_root",
	"tmp_root",
];
const RUNTIME_EXPECTED_KEYS = [
	"mainframe_archive_sha256",
	"installed_tree_algorithm",
	"installed_tree_sha256",
	"pi_package",
	"pi_version",
	"pi_executable_sha256",
	"pi_loader_sha256",
	"pi_extension_sha256",
	"transition_driver_sha256",
	"node_executable_sha256",
	"node_version",
];
const BUDGET_KEYS = ["maximum_context_bytes", "tool_timeout_ms"];
const FIXTURE_KEYS = [
	"session_name",
	"namespace",
	"checkpoint_key",
	"checkpoint_value",
	"checkpoint_importance",
	"handoff_target",
];
const FIXTURE_CONTRACT = Object.freeze({
	session_name: "pi-impact-handoff",
	namespace: "pi-impact-test",
	checkpoint_key: "implementation-root-cause",
	checkpoint_value: "subtract used capacity from total capacity",
	checkpoint_importance: "critical",
	handoff_target: "implementer",
});
const BASE_ENVIRONMENT_KEYS = [
	"CI",
	"HOME",
	"LANG",
	"LC_ALL",
	"LOGNAME",
	"MAINFRAME_EVAL_PROTOCOL",
	"NO_COLOR",
	"PATH",
	"PI_CODING_AGENT_DIR",
	"PI_OFFLINE",
	"TMPDIR",
	"USER",
	"XDG_CACHE_HOME",
	"XDG_CONFIG_HOME",
	"XDG_STATE_HOME",
];

class DriverError extends Error {}

function fail(message) {
	throw new DriverError(message);
}

function isRecord(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, expected, label) {
	if (!isRecord(value)) fail(`${label} must be an object`);
	const actual = Object.keys(value).sort();
	const wanted = [...expected].sort();
	if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
		const missing = wanted.filter((key) => !actual.includes(key));
		const extra = actual.filter((key) => !wanted.includes(key));
		fail(`${label} keys differ (missing=${JSON.stringify(missing)}, extra=${JSON.stringify(extra)})`);
	}
	return value;
}

function requireString(value, label, pattern = null, maximumBytes = 16_384) {
	if (typeof value !== "string" || value.length === 0) fail(`${label} must be a non-empty string`);
	if (Buffer.byteLength(value, "utf8") > maximumBytes) fail(`${label} is too long`);
	if (/[\x00-\x1f\x7f]/u.test(value)) fail(`${label} contains a control character`);
	if (pattern && !pattern.test(value)) fail(`${label} has an invalid value`);
	return value;
}

function requireInteger(value, label, minimum, maximum) {
	if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
		fail(`${label} must be an integer in [${minimum}, ${maximum}]`);
	}
	return value;
}

function requireConstant(value, expected, label) {
	if (value !== expected) fail(`${label} must equal ${JSON.stringify(expected)}`);
	return value;
}

function canonicalize(value) {
	if (Array.isArray(value)) return value.map(canonicalize);
	if (isRecord(value)) {
		const result = Object.create(null);
		for (const key of Object.keys(value).sort()) result[key] = canonicalize(value[key]);
		return result;
	}
	return value;
}

function canonicalBytes(value) {
	return Buffer.from(JSON.stringify(canonicalize(value)), "utf8");
}

function sha256Bytes(value) {
	return createHash("sha256").update(value).digest("hex");
}

function parseJsonStrict(text, label) {
	let offset = 0;

	function parseError(message) {
		fail(`${label} is not strict JSON at byte ${Buffer.byteLength(text.slice(0, offset), "utf8")}: ${message}`);
	}

	function whitespace() {
		while (offset < text.length && /[\t\n\r ]/.test(text[offset])) offset += 1;
	}

	function stringValue() {
		if (text[offset] !== '"') parseError("expected string");
		const start = offset;
		offset += 1;
		let escaped = false;
		while (offset < text.length) {
			const character = text[offset];
			if (escaped) {
				escaped = false;
				offset += 1;
				continue;
			}
			if (character === "\\") {
				escaped = true;
				offset += 1;
				continue;
			}
			if (character === '"') {
				offset += 1;
				try {
					return JSON.parse(text.slice(start, offset));
				} catch (error) {
					parseError(`invalid string: ${error.message}`);
				}
			}
			offset += 1;
		}
		parseError("unterminated string");
	}

	function value() {
		whitespace();
		if (offset >= text.length) parseError("unexpected end of input");
		const character = text[offset];
		if (character === '"') return stringValue();
		if (character === "{") return objectValue();
		if (character === "[") return arrayValue();
		for (const [literal, result] of [["true", true], ["false", false], ["null", null]]) {
			if (text.startsWith(literal, offset)) {
				offset += literal.length;
				return result;
			}
		}
		const match = text.slice(offset).match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/);
		if (!match) parseError("unsupported value");
		offset += match[0].length;
		const result = JSON.parse(match[0]);
		if (!Number.isFinite(result)) parseError("non-finite number");
		return result;
	}

	function objectValue() {
		const result = Object.create(null);
		const keys = new Set();
		offset += 1;
		whitespace();
		if (text[offset] === "}") {
			offset += 1;
			return result;
		}
		while (offset < text.length) {
			whitespace();
			const key = stringValue();
			if (keys.has(key)) parseError(`duplicate object key ${JSON.stringify(key)}`);
			keys.add(key);
			whitespace();
			if (text[offset] !== ":") parseError("expected colon");
			offset += 1;
			result[key] = value();
			whitespace();
			if (text[offset] === "}") {
				offset += 1;
				return result;
			}
			if (text[offset] !== ",") parseError("expected comma or object end");
			offset += 1;
		}
		parseError("unterminated object");
	}

	function arrayValue() {
		const result = [];
		offset += 1;
		whitespace();
		if (text[offset] === "]") {
			offset += 1;
			return result;
		}
		while (offset < text.length) {
			result.push(value());
			whitespace();
			if (text[offset] === "]") {
				offset += 1;
				return result;
			}
			if (text[offset] !== ",") parseError("expected comma or array end");
			offset += 1;
		}
		parseError("unterminated array");
	}

	const result = value();
	whitespace();
	if (offset !== text.length) parseError("trailing content");
	return result;
}

function modeString(metadata) {
	return Number(metadata.mode & 0o7777n).toString(8).padStart(4, "0");
}

function sameFileIdentity(left, right) {
	return left.dev === right.dev && left.ino === right.ino && left.mode === right.mode &&
		left.nlink === right.nlink && left.size === right.size &&
		left.mtimeNs === right.mtimeNs && left.ctimeNs === right.ctimeNs;
}

function readRegularFile(path, label, maximumBytes = MAX_TREE_FILE_BYTES) {
	let before;
	try {
		before = lstatSync(path, { bigint: true });
	} catch (error) {
		fail(`${label} is unavailable: ${error.message}`);
	}
	if (before.isSymbolicLink() || !before.isFile()) fail(`${label} must be a regular non-symlink file`);
	if (before.nlink !== 1n) fail(`${label} must not be hard-linked`);
	if (before.size < 0n || before.size > BigInt(maximumBytes)) fail(`${label} has an unsupported size`);
	let descriptor = -1;
	try {
		descriptor = openSync(path, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW || 0));
		const opened = fstatSync(descriptor, { bigint: true });
		if (!sameFileIdentity(before, opened)) fail(`${label} changed while opening`);
		const output = Buffer.alloc(Number(opened.size));
		let cursor = 0;
		while (cursor < output.length) {
			const count = readSync(descriptor, output, cursor, output.length - cursor, cursor);
			if (count <= 0) fail(`${label} ended before its declared size`);
			cursor += count;
		}
		const after = fstatSync(descriptor, { bigint: true });
		if (!sameFileIdentity(opened, after)) fail(`${label} changed while reading`);
		return { bytes: output, metadata: after };
	} finally {
		if (descriptor >= 0) closeSync(descriptor);
	}
}

function sha256File(path, label, maximumBytes = MAX_TREE_FILE_BYTES) {
	const { bytes, metadata } = readRegularFile(path, label, maximumBytes);
	return { sha256: sha256Bytes(bytes), size_bytes: Number(metadata.size), mode: modeString(metadata), bytes };
}

function canonicalRealDirectory(value, label) {
	requireString(value, label, null, 32_768);
	if (!isAbsolute(value) || resolve(value) !== value) fail(`${label} must be an absolute normalized path`);
	let canonical;
	try {
		canonical = realpathSync(value);
	} catch (error) {
		fail(`${label} is unavailable: ${error.message}`);
	}
	if (canonical !== value) fail(`${label} must be a canonical physical path`);
	const metadata = lstatSync(value, { bigint: true });
	if (metadata.isSymbolicLink() || !metadata.isDirectory()) fail(`${label} must be a real directory`);
	return value;
}

function canonicalRealFile(value, label, executable = false) {
	requireString(value, label, null, 32_768);
	if (!isAbsolute(value) || resolve(value) !== value) fail(`${label} must be an absolute normalized path`);
	let canonical;
	try {
		canonical = realpathSync(value);
	} catch (error) {
		fail(`${label} is unavailable: ${error.message}`);
	}
	if (canonical !== value) fail(`${label} must be a canonical physical path`);
	const { metadata } = readRegularFile(value, label);
	if (executable && (Number(metadata.mode) & 0o111) === 0) fail(`${label} must be executable`);
	if ((Number(metadata.mode) & 0o022) !== 0) fail(`${label} must not be group/world writable`);
	return value;
}

function canonicalFuturePath(value, label) {
	requireString(value, label, null, 32_768);
	if (!isAbsolute(value) || resolve(value) !== value) fail(`${label} must be an absolute normalized path`);
	if (existsSync(value)) fail(`${label} must not exist before the mechanism run`);
	let cursor = dirname(value);
	while (!existsSync(cursor)) {
		const parent = dirname(cursor);
		if (parent === cursor) fail(`${label} has no existing parent`);
		cursor = parent;
	}
	if (realpathSync(cursor) !== cursor) fail(`${label} traverses a symbolic-link ancestor`);
	return value;
}

function pathContains(root, candidate) {
	return candidate === root || candidate.startsWith(`${root}${sep}`);
}

function assertDisjoint(left, right, leftLabel, rightLabel) {
	if (pathContains(left, right) || pathContains(right, left)) {
		fail(`${leftLabel} and ${rightLabel} must not overlap`);
	}
}

function utf8Sort(left, right) {
	return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function snapshotTree(root, label, allowMissing = false) {
	if (!existsSync(root)) {
		if (!allowMissing) fail(`${label} tree is missing`);
		const entries = [];
		return {
			algorithm: SNAPSHOT_TREE_ALGORITHM,
			present: false,
			root_mode: null,
			entry_count: 0,
			file_count: 0,
			directory_count: 0,
			total_file_bytes: 0,
			tree_sha256: sha256Bytes(canonicalBytes(entries)),
			entries,
		};
	}
	canonicalRealDirectory(root, label);
	const rootMetadata = lstatSync(root, { bigint: true });
	const entries = [];
	let fileCount = 0;
	let directoryCount = 0;
	let totalBytes = 0;

	function walk(directory) {
		let names;
		try {
			names = readdirSync(directory).sort(utf8Sort);
		} catch (error) {
			fail(`${label} tree cannot be read: ${error.message}`);
		}
		for (const name of names) {
			requireString(name, `${label} tree entry`, null, 4096);
			if (name === "." || name === ".." || name.includes(sep)) fail(`${label} tree has an unsafe entry name`);
			const path = join(directory, name);
			const relativePath = relative(root, path).split(sep).join("/");
			const metadata = lstatSync(path, { bigint: true });
			if (metadata.isSymbolicLink()) fail(`${label} tree contains a symbolic link: ${relativePath}`);
			if (metadata.isDirectory()) {
				directoryCount += 1;
				entries.push({ path: relativePath, type: "directory", mode: modeString(metadata) });
				walk(path);
			} else if (metadata.isFile()) {
				if (metadata.nlink !== 1n) fail(`${label} tree contains a hard-linked file: ${relativePath}`);
				const binding = sha256File(path, `${label} tree file ${relativePath}`);
				fileCount += 1;
				totalBytes += binding.size_bytes;
				if (totalBytes > MAX_TREE_TOTAL_BYTES) fail(`${label} tree exceeds the total-byte ceiling`);
				entries.push({
					path: relativePath,
					type: "file",
					mode: binding.mode,
					size_bytes: binding.size_bytes,
					sha256: binding.sha256,
				});
			} else {
				fail(`${label} tree contains a special entry: ${relativePath}`);
			}
			if (entries.length > MAX_TREE_ENTRIES) fail(`${label} tree exceeds the entry ceiling`);
		}
	}

	walk(root);
	return {
		algorithm: SNAPSHOT_TREE_ALGORITHM,
		present: true,
		root_mode: modeString(rootMetadata),
		entry_count: entries.length,
		file_count: fileCount,
		directory_count: directoryCount,
		total_file_bytes: totalBytes,
		tree_sha256: sha256Bytes(canonicalBytes(entries)),
		entries,
	};
}

function packageTreeSha256(root, label) {
	canonicalRealDirectory(root, label);
	const entries = [];

	function walk(directory) {
		const names = readdirSync(directory).sort(utf8Sort);
		for (const name of names) {
			requireString(name, `${label} package entry`, null, 4096);
			if (name === "." || name === ".." || name.includes(sep)) fail(`${label} package tree has an unsafe entry name`);
			const path = join(directory, name);
			const relativePath = relative(root, path).split(sep).join("/");
			const metadata = lstatSync(path, { bigint: true });
			if (metadata.isSymbolicLink()) fail(`${label} package tree contains a symbolic link: ${relativePath}`);
			if (metadata.isDirectory()) {
				entries.push({ relative_path: relativePath, path, type: "directory", size: 0 });
				walk(path);
			} else if (metadata.isFile()) {
				if (metadata.nlink !== 1n) fail(`${label} package tree contains a hard-linked file: ${relativePath}`);
				if (metadata.size < 0n || metadata.size > BigInt(MAX_TREE_FILE_BYTES)) {
					fail(`${label} package tree file has an unsupported size: ${relativePath}`);
				}
				entries.push({ relative_path: relativePath, path, type: "file", size: Number(metadata.size) });
			} else {
				fail(`${label} package tree contains a special entry: ${relativePath}`);
			}
			if (entries.length > MAX_TREE_ENTRIES) fail(`${label} package tree exceeds the entry ceiling`);
		}
	}

	walk(root);
	entries.sort((left, right) => utf8Sort(left.relative_path, right.relative_path));
	const digest = createHash("sha256");
	digest.update(PACKAGE_TREE_DOMAIN);
	let totalBytes = 0;
	for (const entry of entries) {
		const encodedPath = Buffer.from(entry.relative_path, "utf8");
		if (entry.type === "directory") {
			digest.update(Buffer.from([68, 0]));
			digest.update(encodedPath);
			digest.update(Buffer.from([0]));
			continue;
		}
		const input = readRegularFile(entry.path, `${label} package file ${entry.relative_path}`);
		if (input.bytes.length !== entry.size) fail(`${label} package file changed while hashing: ${entry.relative_path}`);
		totalBytes += input.bytes.length;
		if (totalBytes > MAX_TREE_TOTAL_BYTES) fail(`${label} package tree exceeds the total-byte ceiling`);
		digest.update(Buffer.from([70, 0]));
		digest.update(encodedPath);
		digest.update(Buffer.from([0]));
		digest.update(Buffer.from(String(entry.size), "ascii"));
		digest.update(Buffer.from([0]));
		digest.update(input.bytes);
	}
	return { algorithm: PACKAGE_TREE_ALGORITHM, sha256: digest.digest("hex"), entry_count: entries.length };
}

function assertPrivateDirectory(path, label) {
	canonicalRealDirectory(path, label);
	const mode = Number(lstatSync(path, { bigint: true }).mode & 0o7777n);
	if (mode !== 0o700) fail(`${label} must have mode 0700`);
}

function assertEmptyDirectory(path, label) {
	assertPrivateDirectory(path, label);
	if (readdirSync(path).length !== 0) fail(`${label} must be empty at driver start`);
}

function assertPrivateAwmTree(snapshot) {
	if (!snapshot.present || snapshot.root_mode !== "0700") fail("AWM root must be present with mode 0700 after init");
	for (const entry of snapshot.entries) {
		const expected = entry.type === "directory" ? "0700" : "0600";
		if (entry.mode !== expected) fail(`AWM entry ${entry.path} must have mode ${expected}`);
	}
}

function normalizeNodeVersion(value) {
	const normalized = String(value || "").replace(/^v/, "");
	if (!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._-]+)?$/.test(normalized)) fail("Node runtime version is malformed");
	return normalized;
}

function probeBashVersion(path) {
	const result = spawnSync(path, ["--noprofile", "--norc", "--version"], {
		encoding: "utf8",
		env: { PATH: SAFE_PATH, LC_ALL: "C", LANG: "C" },
		input: "",
		maxBuffer: 64 * 1024,
		stdio: ["ignore", "pipe", "pipe"],
		timeout: 5_000,
	});
	if (result.error || result.status !== 0 || result.signal !== null) {
		fail(`trusted Bash version probe failed (status=${result.status}, signal=${result.signal}, error=${result.error?.message || "none"})`);
	}
	if (typeof result.stdout !== "string" || typeof result.stderr !== "string" || result.stderr.length !== 0) {
		fail("trusted Bash version probe returned unexpected output");
	}
	const firstLine = result.stdout.trim().split(/\r?\n/u)[0] || "";
	const match = firstLine.match(/^GNU bash, version (\d+\.\d+(?:\.\d+)?\(\d+\)-[A-Za-z0-9._+-]+)(?: |$)/u);
	if (!match) fail("trusted Bash version probe returned an unrecognized version line");
	return match[1];
}

function validateEnvironment() {
	const observed = Object.keys(process.env).sort();
	const allowed = [...BASE_ENVIRONMENT_KEYS];
	if (platform() === "darwin") allowed.push("__CF_USER_TEXT_ENCODING");
	allowed.sort();
	if (observed.length !== allowed.length || observed.some((key, index) => key !== allowed[index])) {
		fail(`driver environment keys differ (observed=${JSON.stringify(observed)}, expected=${JSON.stringify(allowed)})`);
	}
	const fixed = {
		USER: "mainframe-eval",
		LOGNAME: "mainframe-eval",
		PI_OFFLINE: "1",
		PATH: SAFE_PATH,
		LC_ALL: "C",
		LANG: "C",
		NO_COLOR: "1",
		CI: "1",
		MAINFRAME_EVAL_PROTOCOL: "1",
	};
	for (const [key, expected] of Object.entries(fixed)) requireConstant(process.env[key], expected, `environment ${key}`);
	if (platform() === "darwin") {
		if (!/^0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+:0x[0-9A-Fa-f]+$/.test(process.env.__CF_USER_TEXT_ENCODING || "")) {
			fail("Darwin __CF_USER_TEXT_ENCODING has an unexpected value");
		}
	}
	const paths = Object.create(null);
	for (const key of ["HOME", "PI_CODING_AGENT_DIR", "TMPDIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"]) {
		paths[key] = canonicalRealDirectory(process.env[key], `environment ${key}`);
	}
	const values = Object.entries(paths);
	for (let left = 0; left < values.length; left += 1) {
		for (let right = left + 1; right < values.length; right += 1) {
			assertDisjoint(values[left][1], values[right][1], `environment ${values[left][0]}`, `environment ${values[right][0]}`);
		}
	}
	for (const [key, path] of values) assertEmptyDirectory(path, `environment ${key}`);
	const record = {
		allowed_names: allowed,
		values: { ...fixed, __CF_USER_TEXT_ENCODING: process.env.__CF_USER_TEXT_ENCODING || null },
		isolated_paths: paths,
	};
	delete process.env.__CF_USER_TEXT_ENCODING;
	return record;
}

async function installNetworkGuards() {
	const denied = () => { throw new DriverError("network access is disabled in the Pi/AWM fixture driver"); };
	const guarded = [];
	const modules = [
		["node:http", ["get", "request"]],
		["node:https", ["get", "request"]],
		["node:http2", ["connect"]],
		["node:net", ["connect", "createConnection"]],
		["node:tls", ["connect"]],
		["node:dgram", ["createSocket"]],
		["node:dns", ["lookup", "resolve", "resolve4", "resolve6"]],
	];
	for (const [specifier, names] of modules) {
		const imported = await import(specifier);
		const target = imported.default || imported;
		for (const name of names) {
			if (typeof target[name] !== "function") continue;
			try {
				Object.defineProperty(target, name, { value: denied, configurable: false, writable: false });
				guarded.push(`${specifier}.${name}`);
			} catch {
				fail(`could not install network guard ${specifier}.${name}`);
			}
		}
	}
	syncBuiltinESMExports();
	Object.defineProperty(globalThis, "fetch", { value: denied, configurable: false, writable: false });
	guarded.push("globalThis.fetch");
	if ("WebSocket" in globalThis) {
		Object.defineProperty(globalThis, "WebSocket", { value: class { constructor() { denied(); } }, configurable: false, writable: false });
		guarded.push("globalThis.WebSocket");
	}
	return guarded.sort();
}

function validateRequest(request) {
	exactKeys(request, TOP_LEVEL_KEYS, "request");
	requireConstant(request.schema_version, 1, "request.schema_version");
	requireConstant(request.kind, REQUEST_KIND, "request.kind");
	requireConstant(request.claim_scope, CLAIM_SCOPE, "request.claim_scope");

	const binding = exactKeys(request.binding, BINDING_KEYS, "request.binding");
	for (const key of ["preregistration_sha256", "randomization_context_sha256", "assignment_commitment_sha256", "instance_sha256"]) {
		requireString(binding[key], `request.binding.${key}`, SHA256_PATTERN);
	}
	requireString(binding.study_id, "request.binding.study_id", ID_PATTERN);
	requireString(binding.pair_id, "request.binding.pair_id", PAIR_PATTERN);
	requireString(binding.task_id, "request.binding.task_id", ID_PATTERN);
	requireInteger(binding.replicate, "request.binding.replicate", 1, 1000);
	requireString(binding.opaque_arm_id, "request.binding.opaque_arm_id", ARM_PATTERN);
	requireConstant(binding.arm_mode, "treatment", "request.binding.arm_mode");
	requireConstant(binding.phase, "investigate", "request.binding.phase");

	const paths = exactKeys(request.paths, PATH_KEYS, "request.paths");
	paths.mainframe_root = canonicalRealDirectory(paths.mainframe_root, "request.paths.mainframe_root");
	paths.workspace = canonicalRealDirectory(paths.workspace, "request.paths.workspace");
	paths.pi_bin = canonicalRealFile(paths.pi_bin, "request.paths.pi_bin", true);
	paths.node_bin = canonicalRealFile(paths.node_bin, "request.paths.node_bin", true);
	paths.tmp_root = canonicalRealDirectory(paths.tmp_root, "request.paths.tmp_root");
	paths.awm_root = canonicalFuturePath(paths.awm_root, "request.paths.awm_root");
	requireConstant(paths.awm_root, join(homedir(), ".mainframe", "awm"), "request.paths.awm_root");
	requireConstant(paths.tmp_root, process.env.TMPDIR, "request.paths.tmp_root");
	for (const [left, right, leftLabel, rightLabel] of [
		[paths.mainframe_root, paths.workspace, "MAINFRAME root", "workspace"],
		[paths.mainframe_root, homedir(), "MAINFRAME root", "HOME"],
		[paths.mainframe_root, paths.tmp_root, "MAINFRAME root", "TMPDIR"],
		[paths.workspace, homedir(), "workspace", "HOME"],
		[paths.workspace, paths.tmp_root, "workspace", "TMPDIR"],
		[homedir(), paths.tmp_root, "HOME", "TMPDIR"],
	]) assertDisjoint(left, right, leftLabel, rightLabel);

	const runtime = exactKeys(request.runtime_expected, RUNTIME_EXPECTED_KEYS, "request.runtime_expected");
	for (const key of [
		"mainframe_archive_sha256", "installed_tree_sha256", "pi_executable_sha256",
		"pi_loader_sha256", "pi_extension_sha256", "transition_driver_sha256",
		"node_executable_sha256",
	]) requireString(runtime[key], `request.runtime_expected.${key}`, SHA256_PATTERN);
	requireConstant(runtime.installed_tree_algorithm, PACKAGE_TREE_ALGORITHM, "request.runtime_expected.installed_tree_algorithm");
	requireString(runtime.pi_package, "request.runtime_expected.pi_package", NPM_PACKAGE_PATTERN);
	requireString(runtime.pi_version, "request.runtime_expected.pi_version", VERSION_PATTERN);
	requireString(runtime.node_version, "request.runtime_expected.node_version", VERSION_PATTERN);
	normalizeNodeVersion(runtime.node_version);

	const budget = exactKeys(request.budget, BUDGET_KEYS, "request.budget");
	requireConstant(budget.maximum_context_bytes, MAXIMUM_CONTEXT_BYTES, "request.budget.maximum_context_bytes");
	requireInteger(budget.tool_timeout_ms, "request.budget.tool_timeout_ms", 1000, 300_000);

	const fixture = exactKeys(request.fixture, FIXTURE_KEYS, "request.fixture");
	for (const [key, expected] of Object.entries(FIXTURE_CONTRACT)) {
		requireConstant(fixture[key], expected, `request.fixture.${key}`);
	}
	return request;
}

function validateToolResult(result, expectedRoot, expectedAction) {
	if (!isRecord(result) || !isRecord(result.details) || !isRecord(result.details.result)) {
		fail(`mainframe_awm ${expectedAction} returned an invalid result envelope`);
	}
	requireConstant(result.details.root, expectedRoot, `mainframe_awm ${expectedAction} root`);
	requireConstant(result.details.action, expectedAction, `mainframe_awm ${expectedAction} action`);
	const processResult = result.details.result;
	if (processResult.code !== 0 || processResult.timedOut !== false || processResult.signal !== null) {
		fail(`mainframe_awm ${expectedAction} failed (code=${processResult.code}, timed_out=${processResult.timedOut}, signal=${processResult.signal})`);
	}
	if (typeof processResult.stdout !== "string" || typeof processResult.stderr !== "string" ||
		typeof processResult.command !== "string" || !Array.isArray(processResult.args) ||
		!processResult.args.every((item) => typeof item === "string")) {
		fail(`mainframe_awm ${expectedAction} returned malformed process details`);
	}
	return processResult;
}

function sequenceRow(index, action, callId, params, processResult, before, after, previousDigest) {
	const body = {
		index,
		action,
		call_id: callId,
		previous_record_sha256: previousDigest,
		tool_params: params,
		awm_before_sha256: before.tree_sha256,
		awm_after_sha256: after.tree_sha256,
		process_result: processResult,
		stdout_binding: {
			size_bytes: Buffer.byteLength(processResult.stdout, "utf8"),
			sha256: sha256Bytes(Buffer.from(processResult.stdout, "utf8")),
		},
		stderr_binding: {
			size_bytes: Buffer.byteLength(processResult.stderr, "utf8"),
			sha256: sha256Bytes(Buffer.from(processResult.stderr, "utf8")),
		},
	};
	return { ...body, record_sha256: sha256Bytes(canonicalBytes(body)) };
}

function sameTree(left, right) {
	return left.present === right.present && left.root_mode === right.root_mode && left.tree_sha256 === right.tree_sha256;
}

function formatLoadErrors(errors) {
	return errors.map((error) => {
		if (typeof error === "string") return error;
		if (error && typeof error.message === "string") return error.message;
		try { return JSON.stringify(error); } catch { return String(error); }
	}).join(" | ");
}

async function runDriver(requestPath) {
	const environment = validateEnvironment();
	const requestFile = canonicalRealFile(requestPath, "request path");
	const requestInput = sha256File(requestFile, "request path", MAX_REQUEST_BYTES);
	const request = validateRequest(parseJsonStrict(requestInput.bytes.toString("utf8"), "request"));

	const driverPath = realpathSync(fileURLToPath(import.meta.url));
	const nodePath = realpathSync(process.execPath);
	requireConstant(request.paths.node_bin, nodePath, "request.paths.node_bin");
	const driverBinding = sha256File(driverPath, "transition driver");
	const nodeBinding = sha256File(nodePath, "Node executable");
	requireConstant(driverBinding.sha256, request.runtime_expected.transition_driver_sha256, "transition driver digest");
	requireConstant(nodeBinding.sha256, request.runtime_expected.node_executable_sha256, "Node executable digest");
	const nodeVersion = normalizeNodeVersion(process.version);
	requireConstant(nodeVersion, normalizeNodeVersion(request.runtime_expected.node_version), "Node version");

	const piPath = request.paths.pi_bin;
	const piBinding = sha256File(piPath, "Pi executable");
	requireConstant(piBinding.sha256, request.runtime_expected.pi_executable_sha256, "Pi executable digest");
	const piPackagePath = canonicalRealFile(resolve(dirname(piPath), "..", "package.json"), "Pi package manifest");
	const piManifestInput = sha256File(piPackagePath, "Pi package manifest", MAX_REQUEST_BYTES);
	const piManifest = parseJsonStrict(piManifestInput.bytes.toString("utf8"), "Pi package manifest");
	requireConstant(piManifest.name, request.runtime_expected.pi_package, "Pi package name");
	requireConstant(piManifest.version, request.runtime_expected.pi_version, "Pi package version");

	const loaderPath = canonicalRealFile(join(dirname(piPath), "core", "extensions", "loader.js"), "Pi extension loader");
	const loaderBinding = sha256File(loaderPath, "Pi extension loader");
	requireConstant(loaderBinding.sha256, request.runtime_expected.pi_loader_sha256, "Pi loader digest");
	const extensionPath = canonicalRealFile(
		join(request.paths.mainframe_root, "skills", "pi", "extensions", "mainframe.ts"),
		"MAINFRAME Pi extension",
	);
	const extensionBinding = sha256File(extensionPath, "MAINFRAME Pi extension");
	requireConstant(extensionBinding.sha256, request.runtime_expected.pi_extension_sha256, "Pi extension digest");

	const installedBefore = snapshotTree(request.paths.mainframe_root, "installed MAINFRAME");
	const installedPackageBefore = packageTreeSha256(request.paths.mainframe_root, "installed MAINFRAME");
	requireConstant(installedPackageBefore.sha256, request.runtime_expected.installed_tree_sha256, "installed MAINFRAME package-tree digest");
	const workspaceBefore = snapshotTree(request.paths.workspace, "workspace");
	const awmBefore = snapshotTree(request.paths.awm_root, "AWM", true);
	const tmpBefore = snapshotTree(request.paths.tmp_root, "TMPDIR");
	if (awmBefore.present || awmBefore.entry_count !== 0) fail("AWM state must be absent before the fixture run");
	if (tmpBefore.entry_count !== 0) fail("TMPDIR must be empty before the Pi loader runs");

	const networkGuards = await installNetworkGuards();
	const loaderModule = await import(pathToFileURL(loaderPath).href);
	if (typeof loaderModule.loadExtensions !== "function") fail("pinned Pi loader does not export loadExtensions");
	const loaded = await loaderModule.loadExtensions([extensionPath], request.paths.workspace);
	if (!isRecord(loaded) || !Array.isArray(loaded.extensions) || !Array.isArray(loaded.errors)) {
		fail("pinned Pi loader returned an invalid extension result");
	}
	if (loaded.errors.length !== 0) fail(`Pi extension load failed: ${formatLoadErrors(loaded.errors)}`);
	if (loaded.extensions.length !== 1) fail(`expected one loaded Pi extension, received ${loaded.extensions.length}`);
	const extension = loaded.extensions[0];
	if (!(extension.tools instanceof Map)) fail("loaded Pi extension did not expose a tool map");
	const toolEntry = extension.tools.get("mainframe_awm");
	if (!toolEntry || !toolEntry.definition || typeof toolEntry.definition.execute !== "function") {
		fail("loaded Pi extension did not register executable mainframe_awm");
	}
	const registeredTools = [...extension.tools.keys()].map(String).sort();
	const awmTool = toolEntry.definition;
	const context = { cwd: request.paths.workspace, ui: {} };
	const timeoutMs = request.budget.tool_timeout_ms;
	const common = { root: request.paths.mainframe_root, timeoutMs };
	const sequence = [];
	let previousDigest = ZERO_SHA256;

	async function invoke(index, action, params, before) {
		const callId = `${request.binding.opaque_arm_id}-awm-${index}-${action}`;
		const result = await awmTool.execute(callId, params, undefined, undefined, context);
		const processResult = validateToolResult(result, request.paths.mainframe_root, action);
		const after = snapshotTree(request.paths.awm_root, `AWM after ${action}`);
		assertPrivateAwmTree(after);
		const row = sequenceRow(index, action, callId, params, processResult, before, after, previousDigest);
		sequence.push(row);
		previousDigest = row.record_sha256;
		return { processResult, after };
	}

	const initParams = {
		...common,
		action: "init",
		name: request.fixture.session_name,
		namespace: request.fixture.namespace,
		model: "fixture-no-provider",
	};
	const init = await invoke(1, "init", initParams, awmBefore);
	const session = init.processResult.stdout.trim();
	requireString(session, "AWM session id", SESSION_PATTERN);

	const checkpointParams = {
		...common,
		action: "checkpoint",
		session,
		key: request.fixture.checkpoint_key,
		value: request.fixture.checkpoint_value,
		importance: request.fixture.checkpoint_importance,
	};
	const checkpoint = await invoke(2, "checkpoint", checkpointParams, init.after);

	const handoffParams = {
		...common,
		action: "handoff_prepare",
		session,
		message: request.fixture.handoff_target,
		tokens: Math.floor(request.budget.maximum_context_bytes / 4),
	};
	const handoff = await invoke(3, "handoff_prepare", handoffParams, checkpoint.after);
	if (sequence.length !== 3 || sequence[0].previous_record_sha256 !== ZERO_SHA256 ||
		sequence[1].previous_record_sha256 !== sequence[0].record_sha256 ||
		sequence[2].previous_record_sha256 !== sequence[1].record_sha256) {
		fail("AWM action receipt chain is invalid");
	}

	const emittedBytes = Buffer.from(handoff.processResult.stdout, "utf8");
	if (emittedBytes.length === 0 || emittedBytes.length > request.budget.maximum_context_bytes) {
		fail("emitted AWM handoff violates the byte budget");
	}
	const handoffDocument = parseJsonStrict(handoff.processResult.stdout, "emitted AWM handoff");
	if (!isRecord(handoffDocument)) fail("emitted AWM handoff must be an object");
	requireConstant(handoffDocument.type, "handoff", "emitted AWM handoff type");
	requireConstant(handoffDocument.parent_session, session, "emitted AWM parent session");
	requireConstant(handoffDocument.target_agent, request.fixture.handoff_target, "emitted AWM target");
	requireString(handoffDocument.handoff_id, "emitted AWM handoff id", HANDOFF_ID_PATTERN);
	if (!isRecord(handoffDocument.budget)) fail("emitted AWM handoff budget is missing");
	requireConstant(handoffDocument.budget.requested_tokens, handoffParams.tokens, "emitted AWM requested token budget");
	requireConstant(handoffDocument.budget.max_chars, request.budget.maximum_context_bytes, "emitted AWM maximum character budget");
	requireInteger(handoffDocument.budget.actual_chars, "emitted AWM actual characters", 1, request.budget.maximum_context_bytes);

	const persistedPath = canonicalRealFile(
		join(
			request.paths.awm_root,
			"sessions",
			request.fixture.namespace,
			session,
			"handoffs",
			`${handoffDocument.handoff_id}.json`,
		),
		"persisted AWM handoff",
	);
	if (!pathContains(request.paths.awm_root, persistedPath)) fail("persisted AWM handoff escaped AWM_ROOT");
	const persistedBinding = sha256File(persistedPath, "persisted AWM handoff", MAXIMUM_CONTEXT_BYTES);
	if (!emittedBytes.equals(persistedBinding.bytes)) fail("emitted and persisted AWM handoffs differ byte-for-byte");

	const bashCommands = sequence.map((record) => requireString(
		record.process_result.command,
		`AWM operation ${record.index} Bash command`,
		null,
		32_768,
	));
	if (bashCommands.some((command) => command !== bashCommands[0])) {
		fail("AWM operations did not use one identical trusted Bash executable");
	}
	const bashPath = canonicalRealFile(bashCommands[0], "trusted Bash executable", true);
	const bashBinding = sha256File(bashPath, "trusted Bash executable");
	const bashVersion = probeBashVersion(bashPath);

	const installedAfter = snapshotTree(request.paths.mainframe_root, "installed MAINFRAME after AWM");
	const installedPackageAfter = packageTreeSha256(request.paths.mainframe_root, "installed MAINFRAME after AWM");
	const workspaceAfter = snapshotTree(request.paths.workspace, "workspace after AWM");
	const tmpAfter = snapshotTree(request.paths.tmp_root, "TMPDIR after Pi loader");
	if (!sameTree(installedBefore, installedAfter)) fail("installed MAINFRAME tree changed during the AWM fixture");
	if (installedPackageAfter.sha256 !== installedPackageBefore.sha256) fail("installed MAINFRAME package-tree digest changed during the AWM fixture");
	if (!sameTree(workspaceBefore, workspaceAfter)) fail("workspace changed during the read-only treatment investigation fixture");

	const mainframeVersionPath = canonicalRealFile(join(request.paths.mainframe_root, "VERSION"), "MAINFRAME VERSION");
	const mainframeVersion = readRegularFile(mainframeVersionPath, "MAINFRAME VERSION", 1024).bytes.toString("utf8").trim();
	requireString(mainframeVersion, "MAINFRAME version", VERSION_PATTERN);

	return {
		schema_version: 1,
		kind: RECORD_KIND,
		claim_scope: CLAIM_SCOPE,
		binding: request.binding,
		runtime_expected: request.runtime_expected,
		budget: request.budget,
		fixture: request.fixture,
		request: {
			path: requestFile,
			file_sha256: requestInput.sha256,
			canonical_sha256: sha256Bytes(canonicalBytes(request)),
		},
		environment,
		runtime_observed: {
			mainframe_archive_sha256: request.runtime_expected.mainframe_archive_sha256,
			mainframe_version: mainframeVersion,
			installed_tree_algorithm: PACKAGE_TREE_ALGORITHM,
			installed_tree_sha256: installedPackageBefore.sha256,
			pi_package: piManifest.name,
			pi_version: piManifest.version,
			pi_executable: piPath,
			pi_executable_sha256: piBinding.sha256,
			pi_package_manifest_sha256: piManifestInput.sha256,
			pi_loader: loaderPath,
			pi_loader_sha256: loaderBinding.sha256,
			pi_extension: extensionPath,
			pi_extension_sha256: extensionBinding.sha256,
			transition_driver: driverPath,
			transition_driver_sha256: driverBinding.sha256,
			bash_executable: bashPath,
			bash_executable_sha256: bashBinding.sha256,
			bash_version: bashVersion,
			node_executable: nodePath,
			node_executable_sha256: nodeBinding.sha256,
			node_version: nodeVersion,
			registered_tools: registeredTools,
			loaded_mainframe_awm: true,
			network_api_guards: networkGuards,
			provider_adapter_loaded: false,
			provider_inference_requests: 0,
		},
		paths: request.paths,
			snapshots: {
				installed_before: installedBefore,
				installed_after: installedAfter,
				installed_package_before: installedPackageBefore,
				installed_package_after: installedPackageAfter,
			workspace_before: workspaceBefore,
			workspace_after: workspaceAfter,
			awm_before: awmBefore,
			awm_after_init: init.after,
			awm_after_checkpoint: checkpoint.after,
			awm_after_handoff: handoff.after,
			tmp_before: tmpBefore,
			tmp_after: tmpAfter,
			installed_unchanged: true,
			workspace_unchanged: true,
		},
		sequence: {
			algorithm: "sha256-canonical-json-previous-record-v1",
			genesis_sha256: ZERO_SHA256,
			record_count: sequence.length,
			head_sha256: previousDigest,
			records: sequence,
		},
		handoff: {
			session_id: session,
			handoff_id: handoffDocument.handoff_id,
			persisted_path: persistedPath,
			emitted_size_bytes: emittedBytes.length,
			emitted_sha256: sha256Bytes(emittedBytes),
			emitted_raw_utf8: handoff.processResult.stdout,
			persisted_size_bytes: persistedBinding.size_bytes,
			persisted_sha256: persistedBinding.sha256,
			persisted_raw_utf8: persistedBinding.bytes.toString("utf8"),
			emitted_equals_persisted: true,
			maximum_context_bytes: request.budget.maximum_context_bytes,
		},
		non_claims: {
			real_provider_inference: "not-run",
			live_agent_sessions: 0,
			agent_quality: "not-measured",
			comparative_agent_performance: "not-measured",
			developer_productivity: "not-measured",
			machine_safety: "not-established",
			network_containment: "best-effort-node-api-guards-not-os-isolation",
		},
	};
}

const originalStdoutWrite = process.stdout.write;
let capturedStdout = Buffer.alloc(0);
let stdoutIntercepted = false;

function interceptStdout() {
	stdoutIntercepted = true;
	process.stdout.write = function intercepted(chunk, encoding, callback) {
		const resolvedEncoding = typeof encoding === "string" ? encoding : "utf8";
		const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk), resolvedEncoding);
		if (capturedStdout.length + bytes.length > MAX_CAPTURED_STDOUT_BYTES) {
			throw new DriverError("unexpected loader stdout exceeded the capture ceiling");
		}
		capturedStdout = Buffer.concat([capturedStdout, bytes]);
		const completion = typeof encoding === "function" ? encoding : callback;
		if (typeof completion === "function") completion();
		return true;
	};
}

function restoreStdout() {
	if (stdoutIntercepted) process.stdout.write = originalStdoutWrite;
	stdoutIntercepted = false;
}

try {
	if (process.argv.length !== 3) fail("usage: pi-awm-transition-driver.mjs /absolute/path/request.json");
	const requestPath = canonicalRealFile(process.argv[2], "request path");
	interceptStdout();
	const record = await runDriver(requestPath);
	restoreStdout();
	if (capturedStdout.length !== 0) fail("Pi loader or extension wrote unexpected process stdout");
	originalStdoutWrite.call(process.stdout, `${canonicalBytes(record).toString("utf8")}\n`);
} catch (error) {
	restoreStdout();
	const message = error instanceof Error ? error.message : String(error);
	process.stderr.write(`pi-awm-transition-driver: ${message}\n`);
	process.exitCode = 1;
}

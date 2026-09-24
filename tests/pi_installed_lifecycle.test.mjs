/** Opt-in checks of an installed build. All lifecycle changes use disposable settings. */
import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { join, isAbsolute } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

const installedRoot = process.env.MAINFRAME_INSTALLED_ROOT;
const pi = process.env.MAINFRAME_PI_BIN;
const enabled = !!installedRoot && !!pi;
if (enabled) { assert(isAbsolute(installedRoot)); assert(isAbsolute(pi)); }

function fixture() {
  const directory = realpathSync(mkdtempSync(join(tmpdir(), "mainframe-installed-lifecycle-")));
  const home = join(directory, "home");
  const agent = join(directory, "custom Pi configuration with spaces");
  const project = join(directory, "project with spaces");
  const state = join(directory, "state");
  for (const path of [home, agent, project, state]) mkdirSync(path, { mode: 0o700 });
  const env = { PATH: process.env.PATH, USER: process.env.USER, LOGNAME: process.env.LOGNAME,
    HOME: home, XDG_STATE_HOME: state, PI_CODING_AGENT_DIR: agent, MAINFRAME_PI_AGENT_DIR: agent,
    PI_OFFLINE: "1", NO_COLOR: "1", npm_config_cache: join(directory, "npm-cache"),
    npm_config_userconfig: "/dev/null", npm_config_ignore_scripts: "true", npm_config_offline: "true",
    npm_config_audit: "false", npm_config_fund: "false", npm_config_update_notifier: "false" };
  const settings = join(agent, "settings.json");
  const receipt = join(agent, ".mainframe-pi-receipt.json");
  const writeJson = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
  const run = (command, args, expected = 0, options = {}) => {
    const result = spawnSync(command, args, { env, cwd: project, encoding: "utf8", timeout: 90_000, maxBuffer: 2_000_000, ...options });
    assert.equal(result.status, expected, `${command} ${args.join(" ")}\n${result.stdout}\n${result.stderr}\n${result.error || ""}`);
    return result;
  };
  const cli = (...args) => run(join(installedRoot, "bin/mainframe"), ["pi", ...args]);
  return { directory, home, agent, project, state, env, settings, receipt, writeJson, run, cli,
    clean: () => rmSync(directory, { recursive: true, force: true }) };
}

const DISCOVER = String.raw`
import assert from 'node:assert/strict';
import {realpathSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const [piPath, expectedRoot, project, agentDir] = process.argv.slice(2);
const cli=realpathSync(piPath); process.argv[1]=cli;
const piRoot=cli.replace(/\/dist\/(?:bundle\/)?cli\.js$/, '');
const sdk=await import(pathToFileURL(join(piRoot,'dist/index.js')).href);
const settingsManager=sdk.SettingsManager.create(project,agentDir);
const loader=new sdk.DefaultResourceLoader({cwd:project,agentDir,settingsManager,noContextFiles:true,noPromptTemplates:true,noThemes:true});
await loader.reload();
const loaded=loader.getExtensions(); assert.deepEqual(loaded.errors,[]);
assert.equal(loaded.extensions.length,1); assert.equal(realpathSync(loaded.extensions[0].path),join(expectedRoot,'skills/pi/extensions/mainframe.ts'));
const {session}=await sdk.createAgentSession({cwd:project,agentDir,settingsManager,resourceLoader:loader,sessionManager:sdk.SessionManager.inMemory(project)});
try{
 const tools=session.getAllTools().filter(tool=>tool.name.startsWith('mainframe_'));
 assert.equal(tools.length,7); assert.equal(new Set(tools.map(tool=>tool.name)).size,7);
 assert(tools.every(tool=>tool.sourceInfo.source===expectedRoot && tool.sourceInfo.origin==='package'));
 console.log(JSON.stringify({extensions:1,tools:7,source:expectedRoot}));
}finally{session.dispose();}
`;

function discover(f, root = installedRoot) {
  return f.run(process.execPath, ["--input-type=module", "-", pi, root, f.project, f.agent], 0, { input: DISCOVER });
}

test("installed Pi package previews, installs, removes and reinstalls at custom settings paths", { skip: !enabled }, () => {
  const f = fixture();
  try {
    const initial = { packages: [], defaultModel: "preserved-model", nested: { keep: [1, true] } };
    f.writeJson(f.settings, initial);
    const before = readFileSync(f.settings, "utf8");
    assert.equal(JSON.parse(f.cli("status", "--json").stdout).state, "not-installed");
    f.cli("install", "--dry-run");
    assert.equal(readFileSync(f.settings, "utf8"), before); assert(!existsSync(f.receipt));
    f.cli("install", "--yes");
    assert.deepEqual(JSON.parse(readFileSync(f.settings, "utf8")), { ...initial, packages: [installedRoot] });
    assert.equal(JSON.parse(f.cli("status", "--json").stdout).state, "ready");
    discover(f);
    const installed = readFileSync(f.settings, "utf8");
    assert.match(f.cli("install", "--yes").stdout, /changed=false/);
    assert.equal(readFileSync(f.settings, "utf8"), installed);
    f.cli("remove", "--dry-run"); assert.equal(readFileSync(f.settings, "utf8"), installed);
    f.cli("remove", "--yes");
    assert.deepEqual(JSON.parse(readFileSync(f.settings, "utf8")), initial); assert(!existsSync(f.receipt));
    assert.match(f.cli("remove", "--yes").stdout, /changed=false/);
    f.cli("install", "--yes"); discover(f);
  } finally { f.clean(); }
});

test("installed Pi migration replaces a receipted missing source and deduplicates aliases", { skip: !enabled }, () => {
  const f = fixture();
  try {
    const stale = join(f.directory, "missing old install");
    const unrelated = join(f.directory, "unrelated-mainframe"); mkdirSync(unrelated, { mode: 0o700 });
    f.writeJson(join(unrelated, "package.json"), { name: "unrelated", version: "1.0.0", pi: { extensions: [], skills: [] } });
    f.writeJson(f.receipt, { schema_version: 1, manager: "@gtwatts/mainframe-pi", package_source: stale });
    f.writeJson(f.settings, { packages: [stale, unrelated], keep: true });
    assert.equal(JSON.parse(f.cli("status", "--json").stdout).state, "upgrade-needed");
    f.cli("install", "--yes");
    assert.deepEqual(JSON.parse(readFileSync(f.settings, "utf8")).packages, [unrelated, installedRoot]);
    const alias = join(f.directory, "aliased package"); symlinkSync(installedRoot, alias);
    f.writeJson(f.settings, { packages: [unrelated, alias, { source: installedRoot, skills: [] }], keep: true });
    assert.equal(JSON.parse(f.cli("status", "--json").stdout).state, "duplicate");
    f.cli("install", "--yes");
    assert.deepEqual(JSON.parse(readFileSync(f.settings, "utf8")), { packages: [unrelated, installedRoot], keep: true });
    discover(f);
    f.cli("remove", "--yes");
    assert.deepEqual(JSON.parse(readFileSync(f.settings, "utf8")), { packages: [unrelated], keep: true });
    assert(existsSync(join(unrelated, "package.json")));
  } finally { f.clean(); }
});

test("installed Pi lifecycle rejects malformed state and locks, then recovers without settings loss", { skip: !enabled }, () => {
  const f = fixture();
  try {
    writeFileSync(f.settings, "{broken-json\n", { mode: 0o600 });
    f.run(join(installedRoot, "bin/mainframe"), ["pi", "install", "--yes"], 1);
    assert.equal(readFileSync(f.settings, "utf8"), "{broken-json\n"); assert(!existsSync(f.receipt));
    f.writeJson(f.settings, { packages: [], keep: "unchanged" });
    const before = readFileSync(f.settings, "utf8");
    const lock = join(f.agent, ".mainframe-pi-install.lock"); mkdirSync(lock, { mode: 0o700 });
    f.run(join(installedRoot, "bin/mainframe"), ["pi", "install", "--yes"], 75);
    assert.equal(readFileSync(f.settings, "utf8"), before);
    rmSync(lock, { recursive: true });
    f.cli("install", "--yes");
    chmodSync(f.receipt, 0o644);
    const installed = readFileSync(f.settings, "utf8");
    f.run(join(installedRoot, "bin/mainframe"), ["pi", "remove", "--yes"], 1);
    assert.equal(readFileSync(f.settings, "utf8"), installed);
    chmodSync(f.receipt, 0o600);
    f.cli("remove", "--yes"); f.cli("install", "--yes"); discover(f);
  } finally { f.clean(); }
});

test("actual installed npm payload has complete closure and passes native verification from an extracted custom path", { skip: !enabled }, () => {
  const f = fixture();
  try {
    const pack = JSON.parse(f.run("npm", ["pack", "--offline", "--ignore-scripts", "--json", "--pack-destination", f.directory, installedRoot]).stdout)[0];
    const paths = new Set(pack.files.map((file) => file.path));
    const index = JSON.parse(readFileSync(join(installedRoot, "INVOCATION_INDEX.json"), "utf8"));
    const registry = JSON.parse(readFileSync(join(installedRoot, "FUNCTIONS.json"), "utf8"));
    for (const item of [...Object.values(index.modules), ...Object.values(registry.libraries)]) assert(paths.has(item.file), `Missing ${item.file}`);
    for (const required of ["skills/pi/extensions/mainframe.ts", "skills/pi/runtime-verification.mjs", "scripts/dev/verify-pi-runtime.mjs", "lib/runtime-closure.generated.bash"]) assert(paths.has(required), required);
    assert(![...paths].some((path) => /^(?:mcp|lsp|tests|\.github)\//.test(path)));
    // npm tarballs contain files, not directory entries. GNU tar creates implicit
    // directories with the caller's umask; group-writable extraction is not trusted.
    const extract = (name, mask) => {
      const path = join(f.directory, name); mkdirSync(path, { mode: 0o700 });
      const previousMask = process.umask(mask);
      try { f.run("/bin/tar", ["-xzf", join(f.directory, pack.filename), "-C", path]); }
      finally { process.umask(previousMask); }
      return path;
    };
    const unsafeRoot = join(extract("group-writable extraction", 0o002), "package");
    assert.equal(statSync(unsafeRoot).mode & 0o022, 0o020);
    const rejected = f.run(join(unsafeRoot, "bin/mainframe"), ["pi", "install", "--yes"], 1);
    assert.match(rejected.stderr, /package root has unsafe ownership, permissions, or symlink ancestry/);
    assert(!existsSync(f.settings)); assert(!existsSync(f.receipt));
    const extracted = extract("custom extracted package", 0o077);
    const root = join(extracted, "package");
    f.run(join(root, "bin/mainframe"), ["pi", "install", "--yes"]);
    discover(f, root);
    const checked = f.run(process.execPath, [join(root, "scripts/dev/verify-pi-runtime.mjs"), pi]);
    const report = JSON.parse(checked.stdout);
    assert.equal(report.receiptPath, null); assert.equal(report.snapshot.mainframe.root, root);
    assert.equal(Object.values(report.checks).filter((status) => status === "passed").length, 9);
    f.run(join(root, "bin/mainframe"), ["pi", "remove", "--yes"]);
    assert(!JSON.parse(readFileSync(f.settings, "utf8")).packages.includes(root));
  } finally { f.clean(); }
});

#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mainframe-pi-awm-kernel-gate.XXXXXX")"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
}

teardown() {
    if [[ -n "${TEST_ROOT:-}" && "$TEST_ROOT" != "/" &&
          "${TEST_ROOT##*/}" == mainframe-pi-awm-kernel-gate.* ]]; then
        rm -rf -- "$TEST_ROOT"
    fi
}

find_pi() {
    local candidate

    if [[ -n "${MAINFRAME_PI_BIN:-}" ]]; then
        [[ "$MAINFRAME_PI_BIN" == /* && -x "$MAINFRAME_PI_BIN" ]] || return 1
        printf '%s\n' "$MAINFRAME_PI_BIN"
        return 0
    fi
    for candidate in \
        /opt/homebrew/bin/pi \
        /usr/local/bin/pi \
        /home/linuxbrew/.linuxbrew/bin/pi \
        "$HOME/.bun/bin/pi"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v pi 2>/dev/null || return 1
}

find_node() {
    local candidate

    if [[ -n "${MAINFRAME_PI_NODE_BIN:-}" ]]; then
        [[ "$MAINFRAME_PI_NODE_BIN" == /* && -x "$MAINFRAME_PI_NODE_BIN" ]] || return 1
        printf '%s\n' "$MAINFRAME_PI_NODE_BIN"
        return 0
    fi
    for candidate in \
        /opt/homebrew/bin/node \
        /usr/local/bin/node \
        /home/linuxbrew/.linuxbrew/bin/node \
        /usr/bin/node; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v node 2>/dev/null || return 1
}

@test "Pi project AWM production adapter contains no direct project mutator" {
    run rg -n '^[[:space:]]*(awm_project_ensure|_awm_project_mutate_expected)[[:space:]]|MAINFRAME_PROJECT_AWM_SCRIPT|MF_PROJECT_ACTION|runProjectAwm|awm_project_status' \
        "$PROJECT_ROOT/skills/pi/extensions/mainframe.ts"

    [[ "$status" -eq 1 ]]
    [[ -z "$output" ]]
}

@test "Pi project scope routes twelve reviewed operations through durable control plane" {
    local pi_bin node_bin loader_home loader_agent loader_tmp loader_state project
    pi_bin="$(find_pi)" || skip "Pi is not installed"
    node_bin="$(find_node)" || skip "Node.js is not installed"
    loader_home="$TEST_ROOT/home"
    loader_agent="$TEST_ROOT/agent"
    loader_tmp="$TEST_ROOT/tmp"
    loader_state="$TEST_ROOT/state"
    project="$TEST_ROOT/project"
    mkdir -p -- "$loader_home" "$loader_agent" "$loader_tmp" "$loader_state" "$project"
    chmod 700 "$loader_home" "$loader_agent" "$loader_tmp" "$loader_state" "$project"

    run env \
        HOME="$loader_home" \
        XDG_STATE_HOME="$loader_state" \
        PI_CODING_AGENT_DIR="$loader_agent" \
        TMPDIR="$loader_tmp" \
        "$node_bin" --input-type=module - "$PROJECT_ROOT" "$pi_bin" "$project" <<'JS'
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

const root = process.argv[2];
const piBin = process.argv[3];
const project = process.argv[4];
const ambientAwmRoot = join(process.env.HOME, ".mainframe", "awm");
const ledger = join(process.env.XDG_STATE_HOME, "mainframe", "control-plane.jsonl");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function text(result) {
  return result?.content?.map((item) => item?.text || "").join("\n") || "";
}

const loaderPath = join(dirname(realpathSync(piBin)), "core", "extensions", "loader.js");
const { loadExtensions } = await import(pathToFileURL(loaderPath).href);
const extensionPath = join(root, "skills", "pi", "extensions", "mainframe.ts");
const { extensions, errors } = await loadExtensions([extensionPath], root);
assert(errors.length === 0 && extensions.length === 1,
  `Pi extension load failed: ${JSON.stringify(errors)}`);
const awm = extensions[0].tools.get("mainframe_awm")?.definition;
assert(awm, "mainframe_awm is unavailable");

async function projectCall(action, request = {}) {
  const result = await awm.execute(
    `project-${action}-durable`, { scope: "project", action, ...request },
    undefined, undefined, { cwd: project, ui: {} },
  );
  assert(result?.details?.scope === "project" && result.details.action === action,
    `${action} returned the wrong project identity`);
  assert(result.details.controlPlane?.route === "mainframe-awm-project-v1",
    `${action} did not expose its durable route: ${JSON.stringify(result.details)}`);
  return result;
}

const init = await projectCall("init", { name: "pi-durable" });
assert(init.details.status === "ok" && /^[a-f0-9]{12}$/.test(text(init)), text(init));
const secret = "pi-read-secret-62ab";
assert((await projectCall("checkpoint", { key: "phase", value: secret, importance: "high", ttl: 0 })).details.status === "ok");
assert((await projectCall("discovery", { message: "durable discovery", importance: "high" })).details.status === "ok");
assert((await projectCall("progress", { key: "migration", value: "1/2", message: "halfway" })).details.status === "ok");
assert((await projectCall("session")).details.status === "active");
assert((await projectCall("status")).details.status === "active");
const got = await projectCall("get", { key: "phase" });
assert(text(got).includes(secret), `get failed: ${JSON.stringify(got)}`);
for (const [action, request] of [
  ["summary", { tokens: 512 }],
  ["context_for", { query: "durable", tokens: 512 }],
  ["find", { query: "durable", kind: "discovery", limit: 5 }],
  ["handoff_prepare", { message: "reviewer", tokens: 4000, format: "json" }],
]) {
  const result = await projectCall(action, request);
  assert(text(result).includes("untrusted data-only"), `${action} failed: ${JSON.stringify(result)}`);
}
assert((await projectCall("close")).details.status === "ok");
assert(!existsSync(ambientAwmRoot), "Pi project route consulted ambient AWM_ROOT");
assert(!readFileSync(ledger, "utf8").includes(secret), "raw project memory entered durable ledger");

const initialized = await awm.execute(
  "session-init-compatible",
  { scope: "session", action: "init", name: "ordinary-session" },
  undefined,
  undefined,
  { cwd: project, ui: {} },
);
assert(initialized?.details?.result?.code === 0,
  `ordinary session init regressed: ${text(initialized)}`);
const sid = String(initialized.details.result.stdout || "").trim();
assert(/^[a-f0-9]{12}$/.test(sid), "ordinary session init returned an invalid SID");

const checkpointed = await awm.execute(
  "session-checkpoint-compatible",
  { scope: "session", action: "checkpoint", session: sid, key: "compat", value: "preserved" },
  undefined,
  undefined,
  { cwd: project, ui: {} },
);
assert(checkpointed?.details?.result?.code === 0,
  `ordinary session checkpoint regressed: ${text(checkpointed)}`);
JS

    [[ "$status" -eq 0 ]]
}

# MAINFRAME MCP

`mainframe-mcp` is the fail-closed MCP adapter for a matching MAINFRAME
runtime. It gives Pi and other local coding agents a small, reviewed tool
surface without putting the whole shell library behind MCP.

> **Unpublished candidate:** the Python package described here is the v10.2.0
> source candidate. It is not published on PyPI and is not part of the current
> public release assets. Do not use the registry install commands below until a
> release announcement confirms that `mainframe-mcp==10.2.0` is published.

## What the public command exposes

The public `mainframe-mcp` and `mainframe-mcp-server` commands expose exactly
the 26 reviewed `stable-core` tools. There is no public `core` or `full` mode,
and no command-line acknowledgement that widens the tool set.

Every stable-core call is authorized again and delegated through the selected
runtime's public atomic `mainframe invoke --format control-plane-json-v1`
route. The adapter has no direct-shell or legacy-broker execution fallback.
Unknown tools, external commands, and write-capable helpers such as
`ensure_dir` and `atomic_write` are denied. Input schemas are closed; transient
results and metadata-only receipts are bounded and cross-validated before MCP
exposes the kernel-generated Run, ToolCall, PolicyDecision, and Evidence IDs.
Client correlation remains non-authorizing idempotency metadata.

This is an application-level safety boundary, **not an operating-system
sandbox**. MAINFRAME does not confine the rest of an agent, replace macOS or
Linux permissions, or make unrelated shell commands safe. Use normal host
controls, least-privilege credentials, backups, and agent approval policies as
well.

## Runtime compatibility is exact

The Python package is only the MCP adapter; it does not bundle a MAINFRAME
runtime. Package v10.2.0 requires a MAINFRAME v10.2.0 runtime. Before opening
stdio, the command validates an absolute runtime root, its critical layout,
`VERSION`, `FUNCTIONS.json`, `MANIFEST.json`, and the release `SHA256SUMS`
inventory. A missing, unsafe, modified, or version-mismatched runtime fails
before any MCP frame is written to stdout.

Use a verified release installation. The source-only
`--allow-development-root` option requires an explicit `--mainframe-root` and
is for maintainers testing a dirty checkout; it is not a production install
mode.

## Commands

Both installed console names have the same behavior:

```text
mainframe-mcp
mainframe-mcp-server
```

Useful preflight commands are:

```bash
mainframe-mcp --version
mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check
```

`--check` emits one JSON object and exits. A normal no-argument invocation runs
MCP over stdio; stdout is reserved for protocol frames and diagnostics go to
stderr.

The public command ignores ambient `MAINFRAME_ROOT`; use an explicit absolute
`--mainframe-root`, or omit it to use the validated managed Mainframe launcher.
The legacy `MAINFRAME_MCP_TIER` variable is not a public policy control: its presence,
including an empty value or `stable-core`, is rejected at startup.

## Pi and stdio MCP hosts

Pi 0.84.1 does not have a repository-verified direct `mcpServers` configuration
path. Use Mainframe's first-party Pi package for the hand-in-glove Pi
integration:

```bash
mainframe pi status
mainframe pi install --dry-run
mainframe pi install --yes  # run yourself in an external terminal
```

After a changed install, use `/reload` in Pi and run `/mainframe doctor`. See
the root [Pi installation instructions](https://github.com/gtwatts/mainframe#make-mainframe-native-in-pi)
for the lifecycle, backup, and restore contract.

For a separately verified stdio MCP host, resolve `command -v mainframe-mcp`
and configure that absolute command with arguments `--mainframe-root` and the
absolute 10.2.0 runtime root. Use only configuration fields documented and
tested by that host. The installed package command is the supported public
launch boundary; source-checkout launchers are maintainer fixtures.

## Future registry installation

These examples become valid only after publication of the exact version:

```bash
# Ephemeral preflight with uvx
uvx --from mainframe-mcp==10.2.0 \
  mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check

# Ephemeral preflight with pipx
pipx run --spec mainframe-mcp==10.2.0 \
  mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check

# Persistent isolated install
uv tool install mainframe-mcp==10.2.0
# or: pipx install mainframe-mcp==10.2.0
```

Pin the adapter and runtime to the same exact version. Do not substitute an
unpinned `latest` install in agent configuration.

## Stable-core tools

MCP names add the `mainframe_` prefix to these reviewed exports:

```text
array_contains  array_join       is_empty          is_numeric
json_array      json_escape      json_get          json_merge
json_object     json_string      json_valid        output_json
output_success  path_sanitize    to_lower          to_upper
trim_left       trim_right       usop_error_validation
validate_email  validate_int     validate_json     validate_path
validate_regex  validate_semver  validate_url
```

The exact count and names are release canaries. A missing or additional tool is
a startup/test failure, not a compatibility fallback.

## Development verification

Maintainers build the wheel and source distribution outside the checkout:

```bash
tmp_dir="$(mktemp -d)"
python3 .github/scripts/build-mcp-package.py \
  --source mcp \
  --runtime-archive dist/mainframe-10.2.0.tar.gz \
  --output-dir "$tmp_dir"
```

A direct `uv build mcp` intentionally fails: distributable artifacts must
embed the digest of one exact runtime archive's internal `SHA256SUMS`.
Editable source installs remain available for maintainer testing.

The package acceptance suite builds from source and sdist, performs a fresh
non-editable install, exercises both console names and `python -I -m
mainframe_mcp`, and runs real MCP initialize/list/call traffic against an exact
extracted runtime:

```bash
tests/bats/bin/bats tests/mcp_package.bats
```

See [INSTALL.md](INSTALL.md) for the release installation checklist.

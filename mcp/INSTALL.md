# Installing MAINFRAME MCP

The v10.2.0 Python package is currently an **unpublished candidate**. This page
defines the supported installation contract for its eventual publication; it
does not claim that the package is available from PyPI today.

## 1. Install the exact MAINFRAME runtime

Install and verify MAINFRAME v10.2.0 using its release instructions. The MCP
adapter is not a standalone runtime and will not start against v10.1.0, a
future version, or an incomplete source copy.

The selected root must be an absolute path and contain the exact v10.2.0
release inventory, including:

```text
VERSION
FUNCTIONS.json
MANIFEST.json
SHA256SUMS
bin/mainframe
config/invocation-policy.json
config/stable-core.json
lib/common.sh
lib/invoke.sh
```

Critical files and directories must be regular, safely owned, and not writable
by group or other users. The checksum inventory is verified before server
startup.

## 2. Install the adapter after publication

After the project announces that `mainframe-mcp==10.2.0` is published, choose
one isolated installation method:

```bash
uv tool install mainframe-mcp==10.2.0
# or
pipx install mainframe-mcp==10.2.0
```

For an ephemeral check after publication:

```bash
uvx --from mainframe-mcp==10.2.0 \
  mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check

# pipx equivalent
pipx run --spec mainframe-mcp==10.2.0 \
  mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check
```

Do not install an unpinned package name into an agent configuration. The
adapter/runtime version match is exact.

## 3. Preflight the installed command

```bash
mainframe-mcp --version
mainframe-mcp --mainframe-root /absolute/path/to/mainframe-10.2.0 --check
```

The version command must print `mainframe-mcp 10.2.0`. A successful check emits
one compact JSON line containing `ok: true`, `tier: "stable-core"`,
`tool_count: 26`, matching runner/runtime versions, the canonical root, and the
verified inventory identity.

Configuration failures are nonzero, write no stdout, and emit one diagnostic
to stderr. In particular:

- a relative, missing, unsafe, modified, or mismatched root is rejected;
- `--tier` and legacy public tier-selection flags are unsupported; and
- any presence of `MAINFRAME_MCP_TIER`, even `stable-core`, is rejected.

Ambient `MAINFRAME_ROOT` is ignored by the public runner so another process or
project cannot silently replace the selected runtime. Use the explicit
`--mainframe-root` argument, or omit it to select the validated managed
Mainframe launcher.

## 4. Configure an MCP host or Pi

For a stdio MCP host whose configuration has been separately verified, find
the isolated executable:

```bash
command -v mainframe-mcp
```

Configure that absolute command with these arguments, using only fields and a
configuration location documented by the host:

```text
--mainframe-root /absolute/path/to/mainframe-10.2.0
```

Confirm the host advertises exactly 26 tools and that a read/pure call such as
`mainframe_json_get` succeeds. Unknown, external-command, and write-helper calls
must be returned as MCP errors.

The second console name, `mainframe-mcp-server`, is an equivalent compatibility
entry point. Do not configure a host with a checkout-relative Python file or a
source-tree launcher.

Pi 0.84.1 has no repository-verified direct `mcpServers` path. Use the native
Mainframe Pi package instead:

```bash
mainframe pi status
mainframe pi install --dry-run
mainframe pi install --yes  # run yourself in an external terminal
```

After a changed install, use `/reload` in Pi and run `/mainframe doctor`.

## 5. Understand the boundary

The public package always exposes the brokered 26-tool stable-core surface.
Broader internal registry tiers are not an installed-product feature.

MAINFRAME validates and brokers calls made through this MCP server. It is not a
kernel sandbox, container, VM, or blanket restriction on commands the agent can
run through other tools. Keep Pi and other coding agents on least-privilege
accounts, review requested writes, and protect credentials independently.

## Candidate maintainer check

Before publication, maintainers may build the candidate without touching the
repository `dist/` directory:

```bash
candidate_dir="$(mktemp -d)"
python3 .github/scripts/build-mcp-package.py \
  --source mcp \
  --runtime-archive dist/mainframe-10.2.0.tar.gz \
  --output-dir "$candidate_dir"
```

Direct wheel/sdist builds deliberately fail. The candidate builder binds both
artifacts to the exact runtime archive before invoking the isolated backend.

CI verifies wheel/sdist contents and metadata, rebuilds the wheel from the
sdist, installs it non-editably into a fresh environment, exercises both console
scripts and `python -I -m mainframe_mcp`, runs real stdio protocol calls against an
exact extracted runtime, and tests hostile path/import conditions. These checks
are candidate evidence; they do not publish the package or add it to MAINFRAME
release assets.

## Uninstall

Use the same isolated installer that installed the adapter:

```bash
uv tool uninstall mainframe-mcp
# or: pipx uninstall mainframe-mcp
```

Then remove the Mainframe entry from the MCP host. Uninstalling the
adapter does not remove the separately installed MAINFRAME runtime.

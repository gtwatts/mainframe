# MAINFRAME MCP Server - Installation Guide

## Prerequisites

- Python 3.7 or higher
- MAINFRAME installed (at `~/.mainframe` or custom `$MAINFRAME_ROOT`)
- pip package manager

## Installation Steps

### 1. Install MCP SDK

```bash
pip install mcp
```

Or if you're using a virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate
pip install mcp
```

### 2. Make Server Executable

```bash
cd /home/gordontwatts/Documents/Projects/basher/mcp
chmod +x mainframe-mcp-server
```

### 3. Test Installation

```bash
# Test basic imports and structure
python3 test_import.py
```

Expected output:
```
✓ tool_registry imported
✓ executor imported
✓ server imported (MCP SDK available)
✓ FUNCTIONS.json found
✓ Loaded 1500+ functions
✓ Generated 200+ core tools
```

### 4. Configure Claude Code (Recommended)

Add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "mainframe": {
      "command": "/home/gordontwatts/Documents/Projects/basher/mcp/mainframe-mcp-server",
      "env": {
        "MAINFRAME_ROOT": "/home/gordontwatts/Documents/Projects/basher",
        "MAINFRAME_MCP_TIER": "core"
      }
    }
  }
}
```

For full tier (all 1,500+ functions):
```json
{
  "mcpServers": {
    "mainframe": {
      "command": "/home/gordontwatts/Documents/Projects/basher/mcp/mainframe-mcp-server",
      "env": {
        "MAINFRAME_ROOT": "/home/gordontwatts/Documents/Projects/basher",
        "MAINFRAME_MCP_TIER": "full"
      }
    }
  }
}
```

### 5. Restart Claude Code

After adding the MCP server configuration, restart Claude Code to load the new server.

## Verification

Once configured, you should see `mainframe_*` tools available in Claude Code:

- `mainframe_json_object`
- `mainframe_validate_email`
- `mainframe_ensure_dir`
- `mainframe_atomic_write`
- And 200+ more (core tier) or 1,500+ (full tier)

## Troubleshooting

### "Module 'mcp' not found"

```bash
pip install mcp
```

### "FUNCTIONS.json not found"

Ensure `MAINFRAME_ROOT` in your MCP config points to the correct directory:

```bash
# Check if FUNCTIONS.json exists
ls /home/gordontwatts/Documents/Projects/basher/FUNCTIONS.json
```

If not found, you may need to generate it:

```bash
cd /home/gordontwatts/Documents/Projects/basher
./generate_functions_json.sh
```

### Server Not Starting

Check the error output and verify:

1. Python 3.7+ is installed: `python3 --version`
2. MCP SDK is installed: `pip show mcp`
3. Server is executable: `ls -l mcp/mainframe-mcp-server`
4. MAINFRAME_ROOT path is correct

### Testing Manually

```bash
# Run server manually to see error output
cd /home/gordontwatts/Documents/Projects/basher/mcp
./mainframe-mcp-server
```

Press Ctrl+C to stop.

## Deployment to ~/.mainframe

If you want to deploy to standard MAINFRAME location:

```bash
# Copy MCP server to MAINFRAME installation
cp -r /home/gordontwatts/Documents/Projects/basher/mcp ~/.mainframe/

# Update Claude Code config to use new location
# In ~/.claude/mcp.json:
{
  "mcpServers": {
    "mainframe": {
      "command": "~/.mainframe/mcp/mainframe-mcp-server",
      "env": {
        "MAINFRAME_ROOT": "~/.mainframe",
        "MAINFRAME_MCP_TIER": "core"
      }
    }
  }
}
```

## Uninstallation

To remove the MCP server:

1. Remove from `~/.claude/mcp.json`
2. Restart Claude Code
3. Optionally remove files: `rm -rf /home/gordontwatts/Documents/Projects/basher/mcp`

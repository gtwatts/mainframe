# MAINFRAME MCP Server

Exposes MAINFRAME's 2,000+ bash functions as MCP tools for AI agents.

## Installation

```bash
# Install MCP SDK
pip install mcp

# Make server executable
chmod +x mainframe-mcp-server
```

## Usage

### With Claude Code

Add to your `~/.claude/mcp.json`:

```json
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

### Tiers

- **core**: ~200 essential functions (json, validation, ensure, atomic, output)
- **full**: All 1,500+ functions (set MAINFRAME_MCP_TIER=full)

## Tool Naming

Functions are exposed with `mainframe_` prefix:
- `json_object` → `mainframe_json_object`
- `validate_path_safe` → `mainframe_validate_path_safe`
- `ensure_dir` → `mainframe_ensure_dir`

## Examples

### JSON Operations

```python
# Create JSON object
result = await call_tool("mainframe_json_object", {
    "args": ["name=John", "age:number=30", "active:bool=true"]
})
# Output: {"name":"John","age":30,"active":true}

# Parse JSON value
result = await call_tool("mainframe_json_get", {
    "args": ['{"name":"John"}', "name"]
})
# Output: John
```

### Validation

```python
# Validate email
result = await call_tool("mainframe_validate_email", {
    "args": ["user@example.com"]
})

# Validate path safety (prevent traversal attacks)
result = await call_tool("mainframe_validate_path_safe", {
    "args": ["/var/www", "../../../etc/passwd"]
})
```

### File Operations

```python
# Ensure directory exists (idempotent)
result = await call_tool("mainframe_ensure_dir", {
    "args": ["/tmp/test"]
})

# Atomic file write
result = await call_tool("mainframe_atomic_write", {
    "args": ["/tmp/config.json", '{"key":"value"}']
})
```

### String Operations

```python
# Trim whitespace
result = await call_tool("mainframe_trim_string", {
    "args": ["  hello  "]
})
# Output: hello

# Convert to uppercase
result = await call_tool("mainframe_to_upper", {
    "args": ["hello"]
})
# Output: HELLO
```

### Array Operations

```python
# Array unique
result = await call_tool("mainframe_array_unique", {
    "args": ["a b c a b"]
})
# Output: a b c

# Array join
result = await call_tool("mainframe_array_join", {
    "args": [",", "a b c"]
})
# Output: a,b,c
```

## Architecture

```
mainframe-mcp-server (executable)
    ├── server.py (MCP protocol handler)
    ├── tool_registry.py (FUNCTIONS.json parser)
    └── executor.py (bash subprocess execution)
```

## Error Handling

All tool calls return either:
- **Success**: stdout from the bash function
- **Error**: Error message prefixed with "Error: "

## Security

- All arguments are shell-escaped via `shlex.quote()`
- Functions execute with 30-second timeout
- Execution happens in subprocess with controlled environment

## Development

### Testing the Server

```bash
# Test with MCP inspector (if available)
npx @modelcontextprotocol/inspector mcp/mainframe-mcp-server

# Test manually
python3 mcp/server.py
```

### Adding New Functions

Functions are automatically discovered from `FUNCTIONS.json`. To add new tools:

1. Add function to MAINFRAME library
2. Run `./generate_functions_json.sh` to update FUNCTIONS.json
3. Restart MCP server

## Troubleshooting

### "FUNCTIONS.json not found"

Ensure `MAINFRAME_ROOT` environment variable points to your MAINFRAME installation:

```bash
export MAINFRAME_ROOT=~/.mainframe
```

### "MCP SDK not installed"

```bash
pip install mcp
```

### Server Not Starting

Check logs and ensure:
- Python 3.7+ is installed
- `mainframe-mcp-server` is executable (`chmod +x`)
- MAINFRAME is properly installed at `$MAINFRAME_ROOT`

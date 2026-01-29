# MAINFRAME Bash Language Server

Comprehensive IntelliSense for MAINFRAME's 1,900+ bash functions.

## Features

### 1. Smart Autocompletion ✓

- **Trigger**: Type function name or underscore `_`
- **Snippet support**: Auto-generates parameter placeholders
- **Category sorting**: Functions grouped by category (ai, strings, arrays, etc.)
- **Rich preview**: Shows signature and description inline

Example:
```bash
json_obj<TAB>
# Completes to: json_object "${1:key1}=${2:val1}" "${3:key2}=${4:val2}"
```

### 2. Rich Hover Documentation ✓

Hover over any MAINFRAME function to see:
- Full signature with syntax
- Detailed description
- Parameter list with types and defaults
- Return value specification
- Usage examples (if available)
- Related functions
- Library and category info
- Tags (pure, idempotent)

### 3. Signature Help ✓

As you type function arguments, see:
- Parameter names and descriptions
- Required vs optional indicators
- Default values
- Current parameter highlighted

Example:
```bash
validate_int "42" <cursor>
# Shows: min (optional) = null
```

### 4. Document Symbols ✓

- View outline of all MAINFRAME functions used in file
- Quick navigation via breadcrumb
- Shows function signature in detail

### 5. Go-to-Definition ✓

- Jump to library source file
- Opens function implementation in MAINFRAME

## Installation

### Prerequisites

- Node.js 18+
- MAINFRAME installed at `~/.mainframe`
- FUNCTIONS.json generated (run `make metadata` in MAINFRAME root)

### 1. Generate Metadata

```bash
cd /home/gordontwatts/Documents/Projects/basher
./lsp/scripts/generate-lsp-metadata.sh
```

This creates `FUNCTIONS.lsp.json` in `$MAINFRAME_ROOT` with:
- 1,900+ completion items
- Signature help for functions with parameters
- Library and category indexes

### 2. Build TypeScript

```bash
cd lsp
npm install
npm run build
```

This compiles `src/index.ts` to `out/index.js`.

### 3. Configure Editor

#### VS Code

Add to `.vscode/settings.json`:

```json
{
  "bash-ide-vscode.lsp.path": "/home/gordontwatts/Documents/Projects/basher/lsp/out/index.js"
}
```

Or install as VSCode extension (see Extension Setup below).

#### Neovim (nvim-lspconfig)

```lua
require('lspconfig').mainframe_lsp.setup({
  cmd = { 'node', vim.fn.expand('~/.mainframe/lsp/out/index.js'), '--stdio' },
  filetypes = { 'sh', 'bash' },
})
```

#### Emacs (lsp-mode)

```elisp
(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection '("node" "~/.mainframe/lsp/out/index.js" "--stdio"))
  :major-modes '(sh-mode)
  :server-id 'mainframe-lsp))
```

## Architecture

### Data Flow

```
FUNCTIONS.json (source)
    ↓
generate-lsp-metadata.sh (jq transform)
    ↓
FUNCTIONS.lsp.json (optimized for LSP)
    ↓
LSP Server (index.ts)
    ↓
Editor Client
```

### Metadata Structure

```typescript
interface LSPMetadata {
  version: string;
  completions: CompletionItem[];      // 1,900+ items
  signatures: SignatureHelp[];        // Functions with params
  libraries: LibraryInfo[];           // 68 libraries
  categoryIndex: CategoryIndex[];     // Group by category
  stats: {
    total_completions: number;
    total_libraries: number;
    total_signatures: number;
    categories: string[];
  };
}
```

### Completion Item Enhancement

Each completion includes:
- **label**: Function name
- **detail**: Full signature
- **documentation**: Description + metadata
- **insertText**: Snippet with parameter placeholders
- **sortText**: Category-based sorting
- **filterText**: Enhanced search (name + library + description)
- **data**: Rich metadata (params, examples, related functions)

### Signature Help

Built from functions with `params` array:
- Parameter name, position, required/optional
- Documentation for each parameter
- Active parameter highlighting
- Default value display

## LSP Capabilities

| Capability | Status | Description |
|------------|--------|-------------|
| **textDocumentSync** | ✓ | Incremental sync |
| **completionProvider** | ✓ | Smart completion with snippets |
| **hoverProvider** | ✓ | Rich markdown documentation |
| **signatureHelpProvider** | ✓ | Parameter info as you type |
| **documentSymbolProvider** | ✓ | Function call outline |
| **definitionProvider** | ✓ | Jump to library source |

## Development

### Scripts

```bash
npm run build              # Compile TypeScript
npm run watch              # Watch mode for development
npm run generate-metadata  # Regenerate FUNCTIONS.lsp.json
```

### Testing

```bash
# Start server manually for debugging
node out/index.js --stdio

# VSCode Output panel → MAINFRAME Bash LSP
# Shows: "✓ Loaded 1546 functions from 68 libraries"
```

### Adding Examples

Edit `FUNCTIONS.json` to add examples:

```json
{
  "json_object": {
    "description": "Create JSON object",
    "signature": "json_object \"key=val\" [\"key2=val2\" ...]",
    "examples": [
      "json_object \"name=John\" \"age:number=30\"",
      "# Output: {\"name\":\"John\",\"age\":30}"
    ]
  }
}
```

Then regenerate metadata: `./lsp/scripts/generate-lsp-metadata.sh`

### Adding Related Functions

```json
{
  "json_object": {
    "description": "Create JSON object",
    "related": ["json_array", "json_get", "json_merge"]
  }
}
```

## Extension Setup (Optional)

To package as VSCode extension:

1. Install `vsce`:
   ```bash
   npm install -g @vscode/vsce
   ```

2. Add `extension` field to `package.json`:
   ```json
   {
     "activationEvents": ["onLanguage:shellscript"],
     "contributes": {
       "languages": [{
         "id": "shellscript",
         "aliases": ["Shell Script", "bash"]
       }]
     }
   }
   ```

3. Package:
   ```bash
   vsce package
   # Creates: mainframe-bash-lsp-1.0.0.vsix
   ```

4. Install:
   ```bash
   code --install-extension mainframe-bash-lsp-1.0.0.vsix
   ```

## Troubleshooting

### No completions showing

1. Check metadata exists:
   ```bash
   ls -lh ~/.mainframe/FUNCTIONS.lsp.json
   ```

2. Verify metadata is valid:
   ```bash
   jq '.stats' ~/.mainframe/FUNCTIONS.lsp.json
   ```

3. Check LSP server logs:
   - VSCode → Output → MAINFRAME Bash LSP
   - Should show: "✓ Loaded N functions"

### Signature help not working

- Ensure function has `params` in FUNCTIONS.json
- Trigger manually: Ctrl+Shift+Space (or Cmd+Shift+Space on Mac)
- Check logs for signature lookup failures

### Go-to-definition opens wrong location

- Currently jumps to top of library file
- Enhancement needed: parse library to find exact line
- Workaround: Use Ctrl+F to search for function name

## Performance

- **Metadata size**: ~2.5 MB for 1,900 functions
- **Load time**: <100ms (one-time at startup)
- **Completion latency**: <10ms (in-memory lookup)
- **Memory usage**: ~15 MB (metadata + lookup maps)

## Future Enhancements

1. **Exact go-to-definition**: Parse library files to find function line
2. **Inline diagnostics**: Warn about deprecated functions
3. **Function usage analytics**: Track most-used functions
4. **Smart parameter completion**: Context-aware suggestions
5. **Code actions**: Quick fixes for common issues
6. **Workspace symbols**: Search all functions across workspace

## License

MIT - Part of the MAINFRAME project.

## Links

- [MAINFRAME Repository](https://github.com/gtwatts/mainframe)
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [VSCode Extension API](https://code.visualstudio.com/api)

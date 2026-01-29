# Extension Development Guide

Complete guide for developing, testing, and publishing the MAINFRAME Bash Language Support extension.

## Development Workflow

### Initial Setup

```bash
# Clone and navigate
git clone https://github.com/gtwatts/mainframe.git
cd mainframe/lsp

# Install dependencies
npm install

# Start watch mode
npm run watch
```

### Live Development

1. **Open in VS Code**
   ```bash
   code .
   ```

2. **Press F5** to launch Extension Development Host
   - New VS Code window opens
   - Extension is loaded and running
   - Changes require restart (Ctrl+R in Extension Host)

3. **Make Changes**
   - Edit `src/extension.ts` for client-side logic
   - Edit `src/server.ts` for LSP implementation
   - TypeScript compiles automatically (watch mode)

4. **Test Changes**
   - Create/open a `.sh` file in Extension Host
   - Verify functionality works
   - Check Output panel for logs

5. **Debug**
   - Set breakpoints in VS Code
   - F5 starts debugger
   - Or attach to server: Debug > Attach to Server

## Architecture Overview

### Client (extension.ts)

**Responsibilities**:
- Extension activation/deactivation
- Status bar management
- Configuration handling
- Starting/stopping language server
- Command registration

**Key Functions**:
- `activate()` - Extension entry point
- `deactivate()` - Cleanup
- `detectMainframePath()` - Auto-detection
- `startLanguageClient()` - Server lifecycle
- `updateStatusBar()` - UI updates

### Server (server.ts)

**Responsibilities**:
- LSP protocol implementation
- FUNCTIONS.json parsing
- Completion, hover, signature help
- Document analysis

**Key Functions**:
- `onInitialize()` - Server startup
- `onCompletion()` - Autocomplete
- `onHover()` - Documentation
- `onSignatureHelp()` - Parameter hints

### Communication Flow

```
┌─────────────────┐
│  VS Code UI     │
└────────┬────────┘
         │ (User actions)
┌────────▼────────┐
│  Extension      │ extension.ts
│  Client         │ - Status bar
│                 │ - Commands
│                 │ - Config
└────────┬────────┘
         │ (LSP protocol)
┌────────▼────────┐
│  Language       │ server.ts
│  Server         │ - Completions
│                 │ - Hover
│                 │ - Signatures
└────────┬────────┘
         │ (File I/O)
┌────────▼────────┐
│ FUNCTIONS.json  │
└─────────────────┘
```

## Adding Features

### Example: Add Code Actions

1. **Update Server Capabilities**

   ```typescript
   // src/server.ts
   connection.onInitialize((params) => {
     return {
       capabilities: {
         // ... existing
         codeActionProvider: true,
       },
     };
   });
   ```

2. **Implement Handler**

   ```typescript
   connection.onCodeAction((params) => {
     const codeActions: CodeAction[] = [];

     // Example: Quick fix to add source statement
     codeActions.push({
       title: 'Add MAINFRAME source statement',
       kind: CodeActionKind.QuickFix,
       edit: {
         changes: {
           [params.textDocument.uri]: [{
             range: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
             newText: 'source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"\n\n',
           }],
         },
       },
     });

     return codeActions;
   });
   ```

3. **Test**
   - F5 to launch Extension Host
   - Open `.sh` file
   - Trigger code actions (Ctrl+.)

### Example: Add Configuration Setting

1. **Update package.json**

   ```json
   {
     "contributes": {
       "configuration": {
         "properties": {
           "mainframe.newSetting": {
             "type": "boolean",
             "default": true,
             "description": "Description of new setting"
           }
         }
       }
     }
   }
   ```

2. **Access in Extension**

   ```typescript
   // src/extension.ts
   const value = workspace.getConfiguration('mainframe').get<boolean>('newSetting');
   ```

3. **Pass to Server**

   ```typescript
   const clientOptions: LanguageClientOptions = {
     // ...
     initializationOptions: {
       newSetting: value,
     },
   };
   ```

4. **Use in Server**

   ```typescript
   // src/server.ts
   let newSetting: boolean;

   connection.onInitialize((params) => {
     newSetting = params.initializationOptions?.newSetting ?? true;
     // ...
   });
   ```

## Testing

### Manual Testing

**Test Checklist**:

- [ ] **Activation**
  - Extension activates on `.sh` file open
  - Status bar appears
  - No errors in Output panel

- [ ] **Autocomplete**
  - Type function name → suggestions appear
  - Select suggestion → inserts correctly
  - Fuzzy matching works

- [ ] **Hover**
  - Hover on function → documentation appears
  - Markdown formatting correct
  - Examples display properly

- [ ] **Signature Help**
  - Type function + space → parameter hints appear
  - Active parameter highlighted
  - Works for multiple parameters

- [ ] **Configuration**
  - Settings UI accessible
  - Changes take effect
  - Server restarts when needed

- [ ] **Commands**
  - All commands work from Command Palette
  - Status bar click toggles enable/disable

- [ ] **Error Handling**
  - Missing FUNCTIONS.json → warning shown
  - Invalid config → graceful fallback
  - Server crash → auto-restart or error message

### Automated Testing

**Unit Tests** (Vitest):

```typescript
// tests/detection.test.ts
import { describe, it, expect } from 'vitest';
import { detectMainframePath } from '../src/extension';

describe('MAINFRAME Detection', () => {
  it('detects from MAINFRAME_ROOT env var', () => {
    process.env.MAINFRAME_ROOT = '/custom/path';
    const path = detectMainframePath();
    expect(path).toBe('/custom/path');
  });

  it('falls back to ~/.mainframe', () => {
    delete process.env.MAINFRAME_ROOT;
    const path = detectMainframePath();
    expect(path).toContain('.mainframe');
  });
});
```

Run tests:
```bash
npm test                # Run once
npm run test:watch      # Watch mode
npm run test:coverage   # Coverage report
```

**Integration Tests** (VS Code Test):

```typescript
// tests/suite/extension.test.ts
import * as assert from 'assert';
import * as vscode from 'vscode';

suite('Extension Test Suite', () => {
  test('Extension activates', async () => {
    const ext = vscode.extensions.getExtension('mainframe.mainframe-bash-lsp');
    assert.ok(ext);
    await ext.activate();
    assert.strictEqual(ext.isActive, true);
  });
});
```

## Debugging

### Extension Client

1. **Set Breakpoints** in `src/extension.ts`
2. **Press F5** - Extension Host launches with debugger attached
3. **Trigger Code Path** - Breakpoints hit

### Language Server

1. **Start Extension Host** (F5)
2. **Attach Debugger**:
   - Debug panel → "Attach to Server"
   - Or Ctrl+Shift+P → "Debug: Attach to Node Process" → Select LSP server

3. **Set Breakpoints** in `src/server.ts`
4. **Trigger LSP Action** - Breakpoints hit

### Viewing Logs

**Extension Logs**:
- Output panel → "MAINFRAME Bash Language Support"

**Server Logs**:
```typescript
// In server.ts
connection.console.log('Debug message');
connection.console.error('Error message');
```

**Debug Configuration**:

View in `.vscode/launch.json`:
```json
{
  "name": "Attach to Server",
  "type": "node",
  "request": "attach",
  "port": 6009,  // Match port in server debug options
  "restart": true
}
```

## Packaging

### Build for Distribution

```bash
# Clean build
rm -rf out/
npm run compile

# Run tests
npm test

# Lint
npm run lint

# Package
npm run package
```

Output: `mainframe-bash-lsp-1.0.0.vsix`

### Version Management

Update version in `package.json`:
```json
{
  "version": "1.1.0"
}
```

Update `CHANGELOG.md`:
```markdown
## [1.1.0] - 2024-02-01
### Added
- New feature description
```

### Pre-Publishing Checklist

- [ ] Version bumped
- [ ] CHANGELOG.md updated
- [ ] README.md accurate
- [ ] All tests passing
- [ ] No ESLint errors
- [ ] Icon exists (`images/icon.png`)
- [ ] LICENSE file present
- [ ] Repository URL correct

## Publishing

### One-Time Setup

1. **Create Publisher Account**
   - Go to [Azure DevOps](https://dev.azure.com/)
   - Create Personal Access Token (PAT)
   - Scope: Marketplace > Manage

2. **Login with vsce**
   ```bash
   npx vsce login mainframe
   # Enter PAT when prompted
   ```

### Publish to Marketplace

```bash
# Dry run (validate package)
npx vsce package --no-git-tag-version

# Publish
npm run publish

# Or manually
npx vsce publish
```

### Post-Publish

1. **Verify on Marketplace**
   - Visit [VS Code Marketplace](https://marketplace.visualstudio.com/)
   - Search for "MAINFRAME Bash"

2. **Test Installation**
   ```bash
   code --install-extension mainframe.mainframe-bash-lsp
   ```

3. **Tag Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **Create GitHub Release**
   - Go to GitHub repository
   - Releases → Draft new release
   - Tag: v1.0.0
   - Attach `.vsix` file
   - Copy CHANGELOG entry

## Troubleshooting Development

### Server Won't Start

**Check**:
- FUNCTIONS.json exists
- Compiled JS exists in `out/`
- No TypeScript errors

**Debug**:
```bash
# Run server directly
node out/server.js --functions-path ~/.mainframe/FUNCTIONS.json
```

### Extension Host Crashes

**Solutions**:
- Check for infinite loops
- Review async/await usage
- Check Output panel for errors
- Reload Extension Host (Ctrl+R)

### Changes Not Appearing

**Causes**:
- Watch mode not running
- Extension Host not reloaded
- Cached old version

**Solutions**:
```bash
# Restart watch
npm run watch

# In Extension Host: Ctrl+R
# Or restart Extension Host completely
```

### TypeScript Errors

**Common Issues**:

1. **Missing types**
   ```bash
   npm install --save-dev @types/vscode @types/node
   ```

2. **Wrong version**
   ```json
   {
     "engines": {
       "vscode": "^1.75.0"
     },
     "devDependencies": {
       "@types/vscode": "^1.75.0"
     }
   }
   ```

## Performance Optimization

### Startup Time

- Lazy load FUNCTIONS.json (don't block activation)
- Use incremental parsing
- Cache completion items

### Memory Usage

- Don't load entire file into memory
- Use streaming for large files
- Clear unused data structures

### Response Time

- Index functions for O(1) lookup
- Pre-compute completion items
- Use fuzzy search efficiently

## Best Practices

### Code Quality

- Use TypeScript strict mode
- Handle all error cases
- Log important events
- Validate user input

### User Experience

- Show progress for long operations
- Provide helpful error messages
- Don't block UI thread
- Auto-detect whenever possible

### Maintainability

- Clear variable names
- JSDoc for public functions
- Consistent code style
- Modular architecture

---

**Happy developing! 🚀**

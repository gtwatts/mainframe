# MAINFRAME LSP - Quick Start Guide

Get the MAINFRAME Bash Language Support extension running in 5 minutes.

## Installation

### Option 1: From VSIX (Local Testing)

```bash
cd /home/gordontwatts/Documents/Projects/basher/lsp
npm install
npm run compile
npm run package
code --install-extension mainframe-bash-lsp-1.0.0.vsix
```

### Option 2: From Source (Development)

```bash
cd /home/gordontwatts/Documents/Projects/basher/lsp
npm install
code .
# Press F5 to launch Extension Development Host
```

## Verification

1. **Open a bash file**
   ```bash
   echo '#!/bin/bash' > test.sh
   code test.sh
   ```

2. **Check status bar** (bottom right)
   - Should show: ✅ MAINFRAME

3. **Test autocomplete**
   - Type: `json_`
   - Should show: `json_object`, `json_array`, etc.

4. **Test hover**
   - Hover over: `json_object`
   - Should show: Function documentation

## Common Commands

### Development

```bash
# Watch mode (auto-compile)
npm run watch

# Compile once
npm run compile

# Run tests
npm test

# Lint code
npm run lint

# Package extension
npm run package
```

### VS Code Commands

Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac):

- `MAINFRAME: Restart LSP Server`
- `MAINFRAME: Toggle MAINFRAME LSP`
- `MAINFRAME: Show FUNCTIONS.json Path`
- `MAINFRAME: Open Settings`

## Configuration

### Basic Setup

1. Open Settings: `Ctrl+,` (or `Cmd+,`)
2. Search: `mainframe`
3. Configure:
   - `mainframe.enable`: true
   - `mainframe.functionsPath`: (auto-detected)
   - `mainframe.showHints`: true

### Custom FUNCTIONS.json Path

```json
{
  "mainframe.functionsPath": "/custom/path/FUNCTIONS.json"
}
```

## Troubleshooting

### Extension Not Working

1. **Check MAINFRAME installation**
   ```bash
   ls -la ~/.mainframe/FUNCTIONS.json
   ```

2. **Check extension status**
   - Status bar should show ✅ MAINFRAME
   - If ⚠️ Not Found → Set custom path

3. **Check logs**
   - View → Output
   - Select: "MAINFRAME Bash Language Server"

4. **Restart server**
   - Command Palette: `MAINFRAME: Restart LSP Server`

### No Autocomplete

1. **Verify file type**
   - Status bar should say "Shell Script"
   - If not, click and select "Shell Script"

2. **Trigger manually**
   - Press `Ctrl+Space`

3. **Check trigger characters**
   - Type underscore: `_`
   - Type function prefix: `json_`

## Development Workflow

### 1. Make Changes

Edit `src/extension.ts` or `src/server.ts`

### 2. Compile

```bash
npm run watch  # Auto-compile on save
```

### 3. Test

Press `F5` to launch Extension Development Host

### 4. Debug

- Set breakpoints in TypeScript files
- Press `F5` to start debugger
- Debugger attaches automatically

### 5. Package

```bash
npm run package
```

### 6. Test Package

```bash
code --install-extension mainframe-bash-lsp-1.0.0.vsix
```

## Publishing

### One-Time Setup

```bash
# Install vsce
npm install -g @vscode/vsce

# Login to marketplace
vsce login mainframe
```

### Publish

```bash
# Update version in package.json
# Update CHANGELOG.md

# Publish
npm run publish
```

## Quick Reference

### File Structure

```
lsp/
├── src/
│   ├── extension.ts    # VS Code client
│   └── server.ts       # LSP server
├── out/                # Compiled JS (generated)
├── package.json        # Extension manifest
└── README.md           # Documentation
```

### Key Files

- `src/extension.ts` - Extension lifecycle, status bar, commands
- `src/server.ts` - LSP protocol, completions, hover, signatures
- `package.json` - Manifest, dependencies, configuration schema

### Important Functions

**extension.ts**:
- `activate()` - Extension starts
- `deactivate()` - Extension stops
- `detectMainframePath()` - Auto-detect MAINFRAME
- `startLanguageClient()` - Start LSP server

**server.ts**:
- `onInitialize()` - Server starts
- `onCompletion()` - Autocomplete
- `onHover()` - Documentation
- `onSignatureHelp()` - Parameter hints

## Common Tasks

### Add New Command

1. **Register in package.json**:
   ```json
   {
     "contributes": {
       "commands": [{
         "command": "mainframe.myCommand",
         "title": "My Command",
         "category": "MAINFRAME"
       }]
     }
   }
   ```

2. **Implement in extension.ts**:
   ```typescript
   commands.registerCommand('mainframe.myCommand', () => {
     window.showInformationMessage('Hello!');
   });
   ```

### Add New Setting

1. **Define in package.json**:
   ```json
   {
     "contributes": {
       "configuration": {
         "properties": {
           "mainframe.mySetting": {
             "type": "boolean",
             "default": true,
             "description": "My setting description"
           }
         }
       }
     }
   }
   ```

2. **Use in extension.ts**:
   ```typescript
   const value = workspace.getConfiguration('mainframe').get('mySetting');
   ```

### Add LSP Feature

1. **Update server capabilities**:
   ```typescript
   return {
     capabilities: {
       // ... existing
       newFeature: true,
     },
   };
   ```

2. **Implement handler**:
   ```typescript
   connection.onNewFeature((params) => {
     // Implementation
     return result;
   });
   ```

## Resources

### Documentation

- **README.md** - User guide
- **EXTENSION_DEVELOPMENT.md** - Developer guide
- **PACKAGING.md** - Publishing guide
- **CONTRIBUTING.md** - Contribution guide

### External Links

- [VS Code Extension API](https://code.visualstudio.com/api)
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)

## Getting Help

### Issues

GitHub: https://github.com/gtwatts/mainframe/issues

### Logs

```bash
# VS Code Output panel
View → Output → "MAINFRAME Bash Language Server"
```

---

**Ready to go! Press F5 to start developing.** 🚀

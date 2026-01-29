# MAINFRAME Bash LSP Installation Guide

Complete installation instructions for the MAINFRAME Bash Language Support extension.

## Method 1: VS Code Marketplace (Recommended)

**Coming Soon** - Extension will be published to the VS Code Marketplace.

Once published:

1. Open VS Code
2. Press `Ctrl+P` (Windows/Linux) or `Cmd+P` (Mac)
3. Type: `ext install mainframe.mainframe-bash-lsp`
4. Press Enter
5. Reload VS Code

## Method 2: Install from VSIX

### Prerequisites

- VS Code 1.75.0 or higher
- MAINFRAME installed at `~/.mainframe`

### Steps

1. **Download VSIX**

   Download the latest `.vsix` file from [GitHub Releases](https://github.com/gtwatts/mainframe/releases).

2. **Install Extension**

   ```bash
   # Via command line
   code --install-extension mainframe-bash-lsp-1.0.0.vsix

   # Or via VS Code UI:
   # 1. Press Ctrl+Shift+P / Cmd+Shift+P
   # 2. Run: Extensions: Install from VSIX...
   # 3. Select the downloaded .vsix file
   ```

3. **Reload VS Code**

   Press `Ctrl+R` / `Cmd+R` or restart VS Code.

4. **Verify Installation**

   - Open a `.sh` file
   - Check status bar (bottom right) for "✓ MAINFRAME"
   - Try typing a function name like `json_object`

## Method 3: Build from Source

For development or customization.

### Prerequisites

- Node.js 18.0.0 or higher
- npm or yarn
- Git
- MAINFRAME installed

### Steps

1. **Clone Repository**

   ```bash
   git clone https://github.com/gtwatts/mainframe.git
   cd mainframe/lsp
   ```

2. **Install Dependencies**

   ```bash
   npm install
   ```

3. **Compile TypeScript**

   ```bash
   npm run compile
   ```

4. **Package Extension**

   ```bash
   npm run package
   ```

   This creates `mainframe-bash-lsp-1.0.0.vsix` in the current directory.

5. **Install VSIX**

   ```bash
   code --install-extension mainframe-bash-lsp-1.0.0.vsix
   ```

6. **Reload VS Code**

## Post-Installation Configuration

### Verify MAINFRAME Detection

1. Open Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`)
2. Run: `MAINFRAME: Show FUNCTIONS.json Path`
3. Should display: `/home/user/.mainframe/FUNCTIONS.json`

If MAINFRAME is not detected:

### Manual Configuration

1. **Find FUNCTIONS.json Path**

   ```bash
   ls -la ~/.mainframe/FUNCTIONS.json
   # Or custom location:
   ls -la /custom/path/FUNCTIONS.json
   ```

2. **Configure Extension**

   - Open Settings: `Ctrl+,` / `Cmd+,`
   - Search for: `mainframe.functionsPath`
   - Set to: `/full/path/to/FUNCTIONS.json`

3. **Restart LSP Server**

   - Command Palette: `MAINFRAME: Restart LSP Server`

### Optional Settings

Configure these in VS Code settings:

```json
{
  "mainframe.enable": true,
  "mainframe.functionsPath": "",  // Auto-detect if empty
  "mainframe.showHints": true     // Show parameter hints
}
```

## Troubleshooting Installation

### Extension Not Activating

**Symptom**: No status bar item, no autocomplete

**Solutions**:

1. **Check file type**
   - Bottom right corner should say "Shell Script" or "Bash"
   - If not, click and select "Shell Script"

2. **Check extension is enabled**
   - Extensions view (`Ctrl+Shift+X` / `Cmd+Shift+X`)
   - Search for "MAINFRAME"
   - Ensure it's enabled (not grayed out)

3. **Check logs**
   - Output panel: View > Output
   - Select "MAINFRAME Bash Language Server"
   - Look for errors

### Status Bar Shows "⚠️ Not Found"

**Cause**: MAINFRAME installation not detected

**Solutions**:

1. **Verify MAINFRAME is installed**
   ```bash
   ls -la ~/.mainframe/lib/common.sh
   ls -la ~/.mainframe/FUNCTIONS.json
   ```

2. **Set environment variable**
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   export MAINFRAME_ROOT="$HOME/.mainframe"
   ```

3. **Manual path configuration** (see above)

### Status Bar Shows "🚫 Disabled"

**Cause**: Extension is disabled

**Solution**:

1. Click status bar item, or
2. Command Palette: `MAINFRAME: Toggle MAINFRAME LSP`

### No Autocomplete Suggestions

**Solutions**:

1. **Verify FUNCTIONS.json exists**
   ```bash
   cat ~/.mainframe/FUNCTIONS.json | jq '.version'
   ```

2. **Check server is running**
   - Status bar should show "✓ MAINFRAME"

3. **Trigger manually**
   - Press `Ctrl+Space` to trigger autocomplete

4. **Check trigger characters**
   - Type underscore `_` to trigger
   - Type partial function name

### Build Errors from Source

**Error**: `Cannot find module 'vscode'`

**Solution**:
```bash
npm install --save-dev @types/vscode
```

**Error**: `tsc: command not found`

**Solution**:
```bash
npm install -g typescript
# Or use local:
npx tsc
```

## Uninstalling

### Via VS Code

1. Extensions view (`Ctrl+Shift+X` / `Cmd+Shift+X`)
2. Search for "MAINFRAME"
3. Click gear icon → Uninstall

### Via Command Line

```bash
code --uninstall-extension mainframe.mainframe-bash-lsp
```

### Clean Removal

Remove configuration:

1. Open Settings: `Ctrl+,` / `Cmd+,`
2. Search for: `mainframe`
3. Click gear icon → Reset Settings

## Updating

### From Marketplace

VS Code auto-updates extensions by default.

Manual update:
1. Extensions view
2. Find MAINFRAME extension
3. Click "Update" if available

### From VSIX

1. Download new `.vsix` file
2. Uninstall old version
3. Install new version (see Method 2)

### From Source

```bash
cd mainframe/lsp
git pull
npm install
npm run compile
npm run package
code --install-extension mainframe-bash-lsp-1.0.0.vsix
```

## Support

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/gtwatts/mainframe/issues)
- **Discussions**: [GitHub Discussions](https://github.com/gtwatts/mainframe/discussions)

### Reporting Installation Issues

Include:

- VS Code version (`Help > About`)
- Extension version
- Operating system
- MAINFRAME version
- Error logs from Output panel

---

**Need more help?** Open an issue on GitHub with the above information.

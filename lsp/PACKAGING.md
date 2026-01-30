# Extension Packaging Guide

Step-by-step guide for packaging and distributing the MAINFRAME Bash Language Support extension.

## Prerequisites

### Required Tools

```bash
# Node.js and npm (already installed)
node --version  # Should be 18.0.0+

# Install vsce (VS Code Extension Manager)
npm install -g @vscode/vsce

# Verify installation
vsce --version
```

### Required Files Checklist

Before packaging, ensure these files exist:

- [ ] `package.json` - Extension manifest
- [ ] `README.md` - Marketplace description
- [ ] `CHANGELOG.md` - Version history
- [ ] `LICENSE` - MIT license file
- [ ] `images/icon.png` - Extension icon (128x128+)
- [ ] `.vscodeignore` - Files to exclude from package
- [ ] `out/extension.js` - Compiled client code
- [ ] `out/server.js` - Compiled server code

## Pre-Packaging Steps

### 1. Clean Build

```bash
# Remove old artifacts
rm -rf out/
rm -f *.vsix

# Install dependencies
npm install

# Compile TypeScript
npm run compile
```

Verify compilation:
```bash
ls -lh out/
# Should show: extension.js, server.js, and .map files
```

### 2. Run Quality Checks

```bash
# Run tests
npm test

# Run linter
npm run lint

# Check for TypeScript errors
npx tsc --noEmit
```

All checks must pass before packaging.

### 3. Update Version

Edit `package.json`:
```json
{
  "version": "1.0.0"  // Update version number
}
```

**Versioning Guide**:
- **Patch** (1.0.X): Bug fixes, minor changes
- **Minor** (1.X.0): New features, backward compatible
- **Major** (X.0.0): Breaking changes

### 4. Update CHANGELOG.md

Add entry for new version:
```markdown
## [1.0.0] - 2024-01-28

### Added
- Initial release
- Autocomplete for 4,000+ functions
- Hover documentation
- Signature help

### Fixed
- Bug descriptions

### Changed
- Improvement descriptions
```

### 5. Verify README.md

Ensure README contains:
- [ ] Clear description
- [ ] Feature list
- [ ] Installation instructions
- [ ] Configuration examples
- [ ] Troubleshooting section
- [ ] Screenshots/GIFs (optional but recommended)

### 6. Prepare Icon

**Requirements**:
- Size: 128x128 pixels minimum (256x256 or 512x512 recommended)
- Format: PNG with transparency
- Location: `images/icon.png`

**Quick icon creation** (if needed):
```bash
# Using ImageMagick
convert -size 512x512 xc:transparent \
  -font DejaVu-Sans-Bold -pointsize 200 \
  -fill '#4EC9B0' -gravity center \
  -annotate +0+0 'M' \
  images/icon.png
```

### 7. Review .vscodeignore

Ensure unnecessary files are excluded:
```
src/**
tests/**
tsconfig.json
.eslintrc.json
*.map
node_modules/**
.vscode/**
```

Keep only runtime files in package.

## Packaging

### Option 1: Using npm Script (Recommended)

```bash
npm run package
```

This runs: `vsce package`

### Option 2: Manual Packaging

```bash
vsce package
```

### Verify Package

Output should be: `mainframe-bash-lsp-1.0.0.vsix`

**Check package contents**:
```bash
# List files in package
unzip -l mainframe-bash-lsp-1.0.0.vsix

# Or use vsce
vsce ls
```

**Validate size**:
```bash
ls -lh mainframe-bash-lsp-1.0.0.vsix
# Should be < 5 MB typically
```

### Common Packaging Errors

**Error**: `Missing publisher name`
**Fix**: Add to `package.json`:
```json
{
  "publisher": "mainframe"
}
```

**Error**: `Missing README.md`
**Fix**: Ensure README.md exists and is not in `.vscodeignore`

**Error**: `Missing LICENSE`
**Fix**: Create LICENSE file (MIT recommended)

**Error**: `Icon not found`
**Fix**: Create `images/icon.png` or remove icon field from `package.json`

## Testing Packaged Extension

### Local Installation Test

```bash
# Install from .vsix
code --install-extension mainframe-bash-lsp-1.0.0.vsix

# Reload VS Code
# Open a .sh file
# Verify extension works
```

### Test Checklist

After installing packaged extension:

- [ ] Extension appears in Extensions view
- [ ] Status bar shows MAINFRAME status
- [ ] Autocomplete works
- [ ] Hover documentation appears
- [ ] Commands accessible from Command Palette
- [ ] Settings UI works
- [ ] No errors in Output panel

### Uninstall After Testing

```bash
code --uninstall-extension mainframe.mainframe-bash-lsp
```

## Publishing to Marketplace

### One-Time Setup

#### 1. Create Azure DevOps Account

1. Go to [Azure DevOps](https://dev.azure.com/)
2. Sign in with Microsoft account
3. Create organization (if needed)

#### 2. Create Personal Access Token (PAT)

1. Azure DevOps → User Settings → Personal Access Tokens
2. Click "New Token"
3. Configure:
   - **Name**: "VS Code Marketplace"
   - **Organization**: All accessible organizations
   - **Expiration**: 1 year
   - **Scopes**: Marketplace > **Manage**
4. Click "Create"
5. **Copy token** (won't be shown again!)

#### 3. Create Publisher

1. Go to [Marketplace Management](https://marketplace.visualstudio.com/manage)
2. Click "Create Publisher"
3. Fill in:
   - **ID**: `mainframe` (lowercase, no spaces)
   - **Display Name**: "MAINFRAME"
   - **Email**: Your email
4. Click "Create"

#### 4. Login with vsce

```bash
vsce login mainframe
# Enter your PAT when prompted
```

### Publishing

#### Publish New Version

```bash
# Option 1: Using npm script
npm run publish

# Option 2: Manual
vsce publish
```

This will:
1. Package extension
2. Upload to Marketplace
3. Version will be live in ~10 minutes

#### Publish Specific Version

```bash
# Patch increment (1.0.0 → 1.0.1)
vsce publish patch

# Minor increment (1.0.0 → 1.1.0)
vsce publish minor

# Major increment (1.0.0 → 2.0.0)
vsce publish major

# Specific version
vsce publish 1.2.3
```

### Post-Publishing

#### 1. Verify on Marketplace

- Visit: https://marketplace.visualstudio.com/items?itemName=mainframe.mainframe-bash-lsp
- Check description displays correctly
- Verify icon appears
- Test installation button

#### 2. Test Marketplace Installation

```bash
# Install from marketplace
code --install-extension mainframe.mainframe-bash-lsp

# Verify it works
```

#### 3. Create Git Tag

```bash
git tag v1.0.0
git push origin v1.0.0
```

#### 4. Create GitHub Release

1. Go to repository → Releases
2. Click "Draft a new release"
3. Configure:
   - **Tag**: v1.0.0 (use existing)
   - **Title**: "v1.0.0 - Initial Release"
   - **Description**: Copy from CHANGELOG.md
4. Attach `.vsix` file
5. Click "Publish release"

## Distribution Channels

### 1. VS Code Marketplace (Primary)

- **URL**: https://marketplace.visualstudio.com/
- **Installation**: Via VS Code UI or `code --install-extension`
- **Updates**: Automatic

### 2. GitHub Releases

- **URL**: https://github.com/gtwatts/mainframe/releases
- **Installation**: Manual download + install VSIX
- **Updates**: Manual

### 3. Open VSX Registry (Optional)

For non-VS Code editors (VSCodium, Gitpod, etc.):

```bash
# Install ovsx CLI
npm install -g ovsx

# Create account at https://open-vsx.org/

# Publish
ovsx publish mainframe-bash-lsp-1.0.0.vsix -p <your-access-token>
```

## Version Management

### Semantic Versioning

Follow [SemVer](https://semver.org/):

- **1.0.0** - Initial stable release
- **1.0.1** - Bug fix
- **1.1.0** - New feature (backward compatible)
- **2.0.0** - Breaking change

### Pre-Release Versions

For beta testing:

```bash
# Package pre-release
vsce package --pre-release

# Publish pre-release
vsce publish --pre-release
```

Version format: `1.0.0-beta.1`

### Release Cadence

Recommended schedule:
- **Patch**: As needed for critical bugs
- **Minor**: Monthly for new features
- **Major**: Yearly or for breaking changes

## Marketplace Optimization

### README Best Practices

- **First paragraph**: Clear value proposition
- **Screenshots**: Show key features
- **GIFs**: Demonstrate functionality
- **Feature list**: Bullet points with emojis
- **Quick start**: Minimal steps to get started

### Keywords

Optimize for search in `package.json`:
```json
{
  "keywords": [
    "bash",
    "shell",
    "mainframe",
    "autocomplete",
    "intellisense",
    "lsp",
    "language-server"
  ]
}
```

### Categories

Choose relevant categories:
```json
{
  "categories": [
    "Programming Languages",
    "Linters",
    "Snippets"
  ]
}
```

## Metrics and Analytics

### View Extension Statistics

1. Go to [Marketplace Management](https://marketplace.visualstudio.com/manage)
2. Select your publisher
3. View metrics:
   - Installs
   - Daily active users
   - Ratings/reviews
   - Download trends

### Marketplace Q&A

Monitor and respond to:
- Questions in Q&A section
- Reviews (especially negative ones)
- GitHub issues

## Updating Published Extension

### Regular Updates

```bash
# 1. Make changes
# 2. Update version in package.json
# 3. Update CHANGELOG.md
# 4. Test locally
npm run compile
npm test

# 5. Package and test
npm run package
code --install-extension mainframe-bash-lsp-1.1.0.vsix
# Verify it works

# 6. Publish
npm run publish

# 7. Tag and release
git tag v1.1.0
git push origin v1.1.0
```

### Deprecating Old Versions

Cannot delete old versions from Marketplace, but can:
- Publish new version (users auto-update)
- Add deprecation notice to old version's README
- Mention in CHANGELOG

## Troubleshooting Packaging

### Package Too Large

**Problem**: .vsix > 50 MB
**Solutions**:
- Add node_modules to `.vscodeignore`
- Remove source maps (`.map` files)
- Exclude test files
- Compress assets

### Missing Files in Package

**Check** `.vscodeignore`:
```bash
# Should NOT exclude:
# - out/
# - README.md
# - LICENSE
# - images/icon.png
```

### Publishing Fails

**Common causes**:
- Invalid PAT (expired or wrong scope)
- Publisher doesn't exist
- Duplicate version number

**Fix**:
```bash
# Re-login
vsce login mainframe

# Verify publisher
vsce ls-publishers

# Increment version
vsce publish minor
```

## Best Practices

### Before Every Release

1. Clean build (`rm -rf out/ && npm run compile`)
2. All tests pass (`npm test`)
3. No lint errors (`npm run lint`)
4. Version updated
5. CHANGELOG updated
6. Local test of packaged extension

### Release Checklist

```markdown
- [ ] Version bumped
- [ ] CHANGELOG.md updated
- [ ] All tests passing
- [ ] No TypeScript errors
- [ ] No ESLint warnings
- [ ] README.md accurate
- [ ] Package created (`npm run package`)
- [ ] Local test passed
- [ ] Published (`npm run publish`)
- [ ] Marketplace verified
- [ ] Git tagged
- [ ] GitHub release created
```

---

**Ready to package? Run `npm run package` to get started!**

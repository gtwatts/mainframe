# Extension Testing Guide

Comprehensive testing guide for the MAINFRAME Bash Language Support extension.

## Testing Strategy

### Test Pyramid

```
           /\
          /  \  E2E Tests (Manual in Extension Host)
         /____\
        /      \  Integration Tests (LSP protocol)
       /________\
      /          \  Unit Tests (Vitest)
     /____________\
```

## Unit Testing

### Setup

```bash
# Install test dependencies
npm install --save-dev vitest @vitest/ui @vitest/coverage-v8
```

### Running Tests

```bash
# Run all tests
npm test

# Watch mode
npm run test:watch

# Coverage report
npm run test:coverage

# UI mode
npm run test:ui
```

### Writing Unit Tests

Create test file: `tests/detection.test.ts`

```typescript
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { detectMainframePath } from '../src/extension';

describe('MAINFRAME Detection', () => {
  let originalEnv: string | undefined;

  beforeEach(() => {
    originalEnv = process.env.MAINFRAME_ROOT;
  });

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.MAINFRAME_ROOT = originalEnv;
    } else {
      delete process.env.MAINFRAME_ROOT;
    }
  });

  it('should detect from MAINFRAME_ROOT env var', () => {
    process.env.MAINFRAME_ROOT = '/custom/path';
    const path = detectMainframePath();
    expect(path).toBe('/custom/path');
  });

  it('should fall back to ~/.mainframe', () => {
    delete process.env.MAINFRAME_ROOT;
    const path = detectMainframePath();
    expect(path).toContain('.mainframe');
  });

  it('should return null if not found', () => {
    delete process.env.MAINFRAME_ROOT;
    // Mock fs.existsSync to return false
    const path = detectMainframePath();
    // Test based on your system
  });
});
```

### Test Coverage Goals

- **Statements**: > 80%
- **Branches**: > 75%
- **Functions**: > 80%
- **Lines**: > 80%

## Integration Testing

### LSP Protocol Tests

Test server responses to LSP requests.

Create: `tests/lsp.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { TextDocument } from 'vscode-languageserver-textdocument';

describe('LSP Server', () => {
  it('should provide completions for MAINFRAME functions', async () => {
    const document = TextDocument.create(
      'file:///test.sh',
      'shellscript',
      1,
      'json_'
    );

    const position = { line: 0, character: 5 };

    // Mock server.onCompletion handler
    const completions = await getCompletions(document, position);

    expect(completions).toBeDefined();
    expect(completions.length).toBeGreaterThan(0);
    expect(completions[0].label).toMatch(/^json_/);
  });

  it('should provide hover documentation', async () => {
    const document = TextDocument.create(
      'file:///test.sh',
      'shellscript',
      1,
      'json_object'
    );

    const position = { line: 0, character: 5 };

    const hover = await getHover(document, position);

    expect(hover).toBeDefined();
    expect(hover.contents).toContain('json_object');
  });
});
```

## Manual Testing

### Extension Host Testing

The primary testing method for VS Code extensions.

#### Setup

1. **Open extension in VS Code**
   ```bash
   cd lsp
   code .
   ```

2. **Press F5** to launch Extension Development Host

3. **Extension Host opens** with extension loaded

#### Test Checklist

##### Extension Activation

- [ ] Extension activates automatically
- [ ] No errors in Output panel
- [ ] Status bar item appears

##### Auto-Detection

- [ ] MAINFRAME detected at `~/.mainframe`
- [ ] Custom path works (set in settings)
- [ ] Warning shown if not found

##### Autocomplete

- [ ] Triggers on function name typing
- [ ] Triggers on underscore `_`
- [ ] Shows all relevant functions
- [ ] Fuzzy matching works
- [ ] Selection inserts correctly

##### Hover Documentation

- [ ] Hover shows documentation
- [ ] Markdown formatted correctly
- [ ] Function signature displayed
- [ ] Examples shown (when available)
- [ ] Library source shown

##### Signature Help

- [ ] Triggers on space after function name
- [ ] Shows parameter hints
- [ ] Active parameter highlighted
- [ ] Works for multiple parameters

##### Status Bar

- [ ] Shows ✅ when active
- [ ] Shows ⚠️ when MAINFRAME not found
- [ ] Shows 🚫 when disabled
- [ ] Click toggles enable/disable
- [ ] Tooltip shows correct info

##### Commands

Test each command from Command Palette:

- [ ] `MAINFRAME: Restart LSP Server`
  - Server restarts
  - No errors
  - Functionality restored

- [ ] `MAINFRAME: Toggle MAINFRAME LSP`
  - Disables/enables server
  - Status bar updates
  - Autocomplete stops/starts

- [ ] `MAINFRAME: Show FUNCTIONS.json Path`
  - Shows correct path
  - Shows warning if not found

- [ ] `MAINFRAME: Open Settings`
  - Opens settings
  - Focuses on MAINFRAME settings

##### Configuration

- [ ] `mainframe.enable` setting works
  - Disabling stops server
  - Enabling starts server

- [ ] `mainframe.functionsPath` setting works
  - Custom path loads functions
  - Invalid path shows warning

- [ ] `mainframe.showHints` setting works
  - Toggle affects signature help

- [ ] Configuration changes restart server
  - Server restarts automatically
  - New settings take effect

##### Error Handling

- [ ] Missing MAINFRAME → Warning shown
- [ ] Invalid FUNCTIONS.json → Graceful fallback
- [ ] Server crash → Error message
- [ ] Network issues → Timeout handled

##### Performance

- [ ] Activation time < 500ms
- [ ] Autocomplete latency < 50ms
- [ ] Hover latency < 50ms
- [ ] No UI freezing

##### Multi-File Testing

- [ ] Works with multiple `.sh` files
- [ ] Switching files maintains functionality
- [ ] Closing files doesn't break server

##### Edge Cases

- [ ] Empty file
- [ ] File with syntax errors
- [ ] Very large file (10,000+ lines)
- [ ] Non-bash file (shouldn't activate)
- [ ] File with no MAINFRAME functions

### Test Scenarios

#### Scenario 1: Fresh Installation

1. Install extension
2. Open VS Code
3. Create `test.sh`
4. Verify autocomplete works

**Expected**: Extension detects MAINFRAME, provides autocomplete.

#### Scenario 2: Custom Installation

1. Set `mainframe.functionsPath` to custom location
2. Restart server
3. Test autocomplete

**Expected**: Uses custom FUNCTIONS.json.

#### Scenario 3: Server Crash Recovery

1. Kill server process manually
2. Try autocomplete
3. Check error handling

**Expected**: User-friendly error, option to restart.

#### Scenario 4: Configuration Changes

1. Change setting while editing
2. Verify server restarts
3. Verify new setting takes effect

**Expected**: Seamless restart, no interruption.

## Regression Testing

### Before Each Release

Run full test suite:

```bash
# 1. Unit tests
npm test

# 2. Linting
npm run lint

# 3. TypeScript compilation
npm run compile

# 4. Package creation
npm run package

# 5. Manual testing in Extension Host
# Follow checklist above
```

### Automated Regression Suite

Create: `tests/regression.test.ts`

```typescript
describe('Regression Tests', () => {
  it('should not break autocomplete on large files', async () => {
    // Test with 10,000 line file
  });

  it('should handle rapid configuration changes', async () => {
    // Change config 10 times quickly
  });

  it('should not leak memory on file switches', async () => {
    // Open/close 100 files
  });
});
```

## Performance Testing

### Metrics to Track

- **Activation time**: < 500ms
- **Autocomplete latency**: < 50ms
- **Hover latency**: < 50ms
- **Memory usage**: < 30 MB
- **CPU usage**: < 5% idle

### Profiling

```bash
# Start VS Code with profiling
code --inspect-extensions=9229

# Open Chrome DevTools
chrome://inspect

# Profile extension
```

## Security Testing

### Checklist

- [ ] No hardcoded secrets
- [ ] No eval() of user input
- [ ] Path traversal prevented
- [ ] Input validation on all user inputs
- [ ] No arbitrary code execution

### Test Cases

```typescript
describe('Security Tests', () => {
  it('should prevent path traversal', () => {
    const maliciousPath = '../../etc/passwd';
    const result = validatePath(maliciousPath);
    expect(result).toBe(false);
  });

  it('should sanitize user input', () => {
    const maliciousInput = '<script>alert(1)</script>';
    const sanitized = sanitizeInput(maliciousInput);
    expect(sanitized).not.toContain('<script>');
  });
});
```

## Compatibility Testing

### VS Code Versions

Test on:
- [ ] Minimum: VS Code 1.75.0
- [ ] Current stable release
- [ ] Insiders build

### Operating Systems

Test on:
- [ ] Linux (Ubuntu, Fedora)
- [ ] macOS
- [ ] Windows

### MAINFRAME Versions

Test with:
- [ ] Latest release
- [ ] Previous release
- [ ] Development version

## Test Automation

### GitHub Actions Workflow

Create: `.github/workflows/test.yml`

```yaml
name: Test Extension

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm install

      - name: Run linter
        run: npm run lint

      - name: Run tests
        run: npm test

      - name: Build extension
        run: npm run compile

      - name: Package extension
        run: npm run package

      - name: Upload VSIX
        uses: actions/upload-artifact@v3
        with:
          name: extension
          path: '*.vsix'
```

## Debugging Tests

### VS Code Test Debugging

1. **Set breakpoints** in test file
2. **Debug configuration** in `.vscode/launch.json`:

```json
{
  "name": "Debug Tests",
  "type": "extensionHost",
  "request": "launch",
  "args": [
    "--extensionDevelopmentPath=${workspaceFolder}",
    "--extensionTestsPath=${workspaceFolder}/out/test"
  ],
  "outFiles": [
    "${workspaceFolder}/out/test/**/*.js"
  ]
}
```

3. **Press F5** with "Debug Tests" selected

### Vitest UI Debugging

```bash
npm run test:ui
```

Opens browser with interactive test UI.

## Test Documentation

### Test Naming Convention

```typescript
describe('Component/Feature', () => {
  it('should do something when condition', () => {
    // Test
  });
});
```

### Test Structure

```typescript
it('should provide completions for MAINFRAME functions', () => {
  // Arrange
  const document = createDocument('json_');
  const position = { line: 0, character: 5 };

  // Act
  const completions = getCompletions(document, position);

  // Assert
  expect(completions).toBeDefined();
  expect(completions.length).toBeGreaterThan(0);
});
```

## Pre-Release Testing

### Final Checklist

Before publishing:

- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Manual testing checklist complete
- [ ] Performance metrics acceptable
- [ ] No security issues
- [ ] Tested on all target platforms
- [ ] Documentation updated
- [ ] CHANGELOG updated

### Beta Testing

1. **Create pre-release**
   ```bash
   vsce package --pre-release
   ```

2. **Distribute to testers**
   - Share `.vsix` file
   - Provide test scenarios

3. **Collect feedback**
   - Bug reports
   - Feature requests
   - Performance issues

4. **Fix issues** before stable release

## Continuous Monitoring

### After Release

Monitor:
- GitHub issues
- Marketplace reviews
- VS Code logs (if users share)
- Crash reports

### Regression Prevention

When fixing bugs:

1. **Write failing test** that reproduces bug
2. **Fix bug**
3. **Verify test passes**
4. **Add to regression suite**

## Test Metrics

### Track Over Time

- **Code coverage**: Should trend upward
- **Test count**: Should increase with features
- **Bug reports**: Should decrease
- **Test execution time**: Should stay low

---

**Testing is crucial for quality. Run tests before every commit!** ✅

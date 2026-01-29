# Contributing to MAINFRAME Bash Language Support

Thank you for your interest in contributing to the MAINFRAME Bash Language Support extension!

## Development Setup

### Prerequisites

- **Node.js** 18.0.0 or higher
- **npm** or **yarn**
- **VS Code** 1.75.0 or higher
- **MAINFRAME** installed at `~/.mainframe`

### Clone and Build

```bash
# Clone repository
git clone https://github.com/gtwatts/mainframe.git
cd mainframe/lsp

# Install dependencies
npm install

# Compile TypeScript
npm run compile

# Watch mode for development
npm run watch
```

### Running in Development

1. Open the `lsp/` directory in VS Code
2. Press `F5` to launch Extension Development Host
3. A new VS Code window opens with the extension loaded
4. Open a `.sh` or `.bash` file to test functionality

### Testing Changes

```bash
# Run tests
npm test

# Watch mode
npm run test:watch

# Coverage report
npm run test:coverage
```

## Project Structure

```
lsp/
├── src/
│   ├── extension.ts    # VS Code extension client
│   └── server.ts       # Language server implementation
├── scripts/
│   └── generate-lsp-metadata.sh  # Metadata generator
├── out/                # Compiled JavaScript
├── package.json        # Extension manifest
└── tsconfig.json       # TypeScript configuration
```

## Code Style

- **TypeScript** with strict mode enabled
- **ESLint** for linting (`npm run lint`)
- **Prettier** for formatting (recommended)

### Naming Conventions

- **Functions**: camelCase (`detectMainframePath`)
- **Classes**: PascalCase (`LanguageClient`)
- **Constants**: UPPER_SNAKE_CASE (`MAINFRAME_ROOT`)
- **Interfaces**: PascalCase with `I` prefix optional

### Code Quality

- Use TypeScript types explicitly (avoid `any` when possible)
- Write JSDoc comments for public functions
- Handle errors gracefully with try/catch
- Log important events to connection.console

## Making Changes

### Adding Features

1. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Implement changes**
   - Update `src/extension.ts` for client-side features
   - Update `src/server.ts` for LSP capabilities
   - Add tests for new functionality

3. **Test thoroughly**
   - Manual testing in Extension Development Host
   - Automated tests pass (`npm test`)
   - No ESLint errors (`npm run lint`)

4. **Update documentation**
   - Update README.md if adding user-facing features
   - Update CHANGELOG.md with your changes
   - Add JSDoc comments to new functions

5. **Commit and push**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   git push origin feature/your-feature-name
   ```

6. **Create Pull Request**
   - Describe what the PR does
   - Reference any related issues
   - Include screenshots for UI changes

### Fixing Bugs

1. **Create an issue** (if one doesn't exist)
   - Describe the bug
   - Include steps to reproduce
   - Include VS Code version, extension version, MAINFRAME version

2. **Create a branch**
   ```bash
   git checkout -b fix/bug-description
   ```

3. **Fix the bug**
   - Write a test that reproduces the bug
   - Fix the bug
   - Verify test now passes

4. **Commit and push**
   ```bash
   git add .
   git commit -m "fix: description of bug fix"
   git push origin fix/bug-description
   ```

5. **Create Pull Request**

## Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: add signature help for MAINFRAME functions
fix: handle missing FUNCTIONS.json gracefully
docs: update installation instructions
refactor: extract status bar logic to separate file
```

## Pull Request Guidelines

### Before Submitting

- [ ] Code compiles without errors (`npm run compile`)
- [ ] Tests pass (`npm test`)
- [ ] No ESLint errors (`npm run lint`)
- [ ] CHANGELOG.md updated
- [ ] Documentation updated (if needed)

### PR Description

Include:
- **What** the PR does
- **Why** the change is needed
- **How** the change works
- **Testing** steps to verify the change

## Adding LSP Capabilities

### Example: Adding a New LSP Feature

1. **Update server capabilities** in `src/server.ts`:

```typescript
return {
  capabilities: {
    textDocumentSync: TextDocumentSyncKind.Incremental,
    completionProvider: { ... },
    hoverProvider: true,
    // Add your new capability
    newFeatureProvider: true,
  },
};
```

2. **Implement the handler**:

```typescript
connection.onNewFeature((params) => {
  // Your implementation
  return result;
});
```

3. **Update client** if needed in `src/extension.ts`

4. **Test** in Extension Development Host

## Testing

### Manual Testing Checklist

Test these scenarios:

- [ ] Extension activates on `.sh` file open
- [ ] Autocomplete shows MAINFRAME functions
- [ ] Hover shows function documentation
- [ ] Status bar shows correct status
- [ ] Commands work from Command Palette
- [ ] Configuration changes take effect
- [ ] Server restarts cleanly

### Automated Testing

Add tests to `tests/` directory:

```typescript
import { describe, it, expect } from 'vitest';

describe('Function Detection', () => {
  it('should detect MAINFRAME installation', () => {
    const path = detectMainframePath();
    expect(path).toBeTruthy();
  });
});
```

## Documentation

### JSDoc Comments

Use JSDoc for all public functions:

```typescript
/**
 * Detect MAINFRAME installation path
 *
 * Checks environment variable and default location.
 *
 * @returns Path to MAINFRAME root, or null if not found
 */
function detectMainframePath(): string | null {
  // ...
}
```

### README Updates

When adding features:
- Update Features section
- Add to Usage examples
- Update Configuration table
- Add to Commands table

## Release Process

(For maintainers)

1. **Update version** in `package.json`
2. **Update CHANGELOG.md** with release date
3. **Commit changes**
   ```bash
   git commit -m "chore: release v1.1.0"
   ```
4. **Tag release**
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
5. **Build package**
   ```bash
   npm run package
   ```
6. **Publish to marketplace**
   ```bash
   npm run publish
   ```

## Questions?

- **Issues**: [GitHub Issues](https://github.com/gtwatts/mainframe/issues)
- **Discussions**: [GitHub Discussions](https://github.com/gtwatts/mainframe/discussions)

## Code of Conduct

Be respectful, constructive, and professional in all interactions.

---

Thank you for contributing to MAINFRAME! 🎉

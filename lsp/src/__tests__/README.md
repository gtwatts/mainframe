# MAINFRAME LSP Test Suite

Comprehensive test suite following TDD principles with 95.83% function coverage.

## Quick Start

```bash
# Run all tests
bun test

# Watch mode (re-run on file changes)
bun test:watch

# Coverage report
bun test:coverage

# Interactive UI
bun test:ui
```

## Directory Structure

```
__tests__/
├── fixtures/           # Test data
│   ├── test-metadata.json
│   └── invalid-metadata.json
├── unit/              # Unit tests (135 tests)
│   ├── metadata.test.ts
│   ├── completion.test.ts
│   ├── hover.test.ts
│   └── signature.test.ts
├── integration/       # Integration tests (44 tests)
│   └── server.test.ts
└── e2e/              # End-to-end tests (35 tests)
    └── vscode-scenarios.test.ts
```

## Test Fixtures

### test-metadata.json
Mock `FUNCTIONS.lsp.json` with 5 sample functions for testing:
- `json_object` - JSON library
- `array_sort` - Arrays library
- `http_get` - HTTP library
- `validate_email` - Validation library
- `trim_string` - Strings library

### invalid-metadata.json
Intentionally malformed JSON for error handling tests.

## Writing Tests

### Test Structure (AAA Pattern)

```typescript
it('describes what the test does', () => {
  // Arrange - Set up test data
  const loader = new MetadataLoader(testMetadataPath);
  loader.load();

  // Act - Perform the operation
  const result = loader.getFunction('json_object');

  // Assert - Verify expectations
  expect(result).toBeDefined();
  expect(result?.name).toBe('json_object');
});
```

### Test Naming Convention

```typescript
describe('ClassName', () => {
  describe('methodName', () => {
    it('returns expected result for valid input', () => {});
    it('returns null for invalid input', () => {});
    it('throws error for missing required parameter', () => {});
    it('handles edge case gracefully', () => {});
  });
});
```

## Test Categories

### Unit Tests
Test individual classes in isolation with mocked dependencies.

**MetadataLoader** (52 tests)
- Constructor behavior
- Loading metadata
- Function lookup
- Search operations
- Statistics
- Edge cases

**CompletionProvider** (29 tests)
- All completions
- Prefix filtering
- Documentation formatting
- Edge cases

**HoverProvider** (30 tests)
- Word extraction
- Hover content
- Position handling
- Edge cases

**SignatureHelpProvider** (24 tests)
- Signature generation
- Parameter tracking
- Context detection
- Edge cases

### Integration Tests
Test multiple components working together.

**server.test.ts** (44 tests)
- End-to-end workflows
- Multiple providers
- Document updates
- Error handling
- Performance
- Metadata changes

### E2E Tests
Simulate real VS Code user scenarios.

**vscode-scenarios.test.ts** (35 tests)
- User typing function names
- Hovering for documentation
- Signature help while typing
- Editing complex scripts
- Exploring functions
- Refactoring code
- Unknown function handling
- Performance at scale

## Coverage Requirements

**Minimum**: 80% for lines, functions, branches, statements

**Current**:
- Lines: 99.53%
- Functions: 95.83%

## Best Practices

### ✅ DO

```typescript
// Use descriptive test names
it('returns completion items for all functions', () => {});

// Test behavior, not implementation
expect(completions.length).toBe(5);

// Use beforeEach for common setup
beforeEach(() => {
  loader = new MetadataLoader(testMetadataPath);
  loader.load();
});

// Test edge cases
it('handles empty document', () => {});
it('handles null input', () => {});
it('handles very long strings', () => {});

// Test error paths
it('returns error for nonexistent file', () => {});
```

### ❌ DON'T

```typescript
// Don't test implementation details
expect(provider.cache.size).toBe(5); // BAD - internal state

// Don't use magic numbers
expect(completions.length).toBe(5); // OK if explained
expect(completions.length).toBe(47); // BAD - where does 47 come from?

// Don't share state between tests
let sharedLoader; // BAD - tests should be independent

// Don't skip error cases
// it.skip('handles invalid input', () => {}); // BAD
```

## Mocking

### TextDocument
```typescript
import { TextDocument } from 'vscode-languageserver-textdocument';

const document = TextDocument.create(
  'file:///test.sh',
  'shellscript',
  1,
  'json_object "name=test"'
);
```

### Position
```typescript
import { Position } from 'vscode-languageserver-types';

const position = Position.create(0, 5); // Line 0, character 5
```

### MetadataLoader
```typescript
const testMetadataPath = path.join(__dirname, '../fixtures/test-metadata.json');
const loader = new MetadataLoader(testMetadataPath);
loader.load();
```

## Performance Tests

All performance tests have time limits:

```typescript
it('loads metadata efficiently on startup', () => {
  const startTime = Date.now();
  loader.load();
  const endTime = Date.now();

  expect(endTime - startTime).toBeLessThan(1000); // < 1 second
});
```

## Common Patterns

### Testing Completions
```typescript
const completions = provider.getCompletionsByPrefix('json_');
expect(completions.length).toBe(1);
expect(completions[0].label).toBe('json_object');
expect(completions[0].documentation).toBeDefined();
```

### Testing Hover
```typescript
const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'json_object');
const hover = provider.getHover(document, Position.create(0, 5));

expect(hover).not.toBeNull();
const value = hover?.contents && typeof hover.contents === 'object' ? hover.contents.value : '';
expect(value).toContain('json_object');
```

### Testing Signature Help
```typescript
const document = TextDocument.create('file:///test.sh', 'shellscript', 1, 'http_get ');
const signature = provider.getSignatureHelp(document, Position.create(0, 9));

expect(signature).not.toBeNull();
expect(signature?.signatures).toHaveLength(1);
expect(signature?.activeParameter).toBe(0);
```

## Debugging Tests

### Run specific test
```bash
# Run one file
bun test src/__tests__/unit/metadata.test.ts

# Run one describe block
bun test -t "MetadataLoader"

# Run one test
bun test -t "returns function metadata by exact name"
```

### Debug mode
```bash
# Add --inspect flag
bun test --inspect

# Or use debugger statement
it('test name', () => {
  debugger; // Execution pauses here
  const result = loader.getFunction('json_object');
});
```

### Verbose output
```bash
# Show all test output
bun test --reporter=verbose

# Show only failures
bun test --reporter=tap
```

## CI/CD Integration

Tests run automatically on:
1. Pre-commit hook
2. Pull requests
3. Main branch merges

**Pipeline fails if**:
- Any test fails
- Coverage < 80%
- Tests take > 5 seconds

## Adding New Tests

### 1. Create test file
```bash
touch src/__tests__/unit/new-feature.test.ts
```

### 2. Write failing test (RED)
```typescript
import { describe, it, expect } from 'vitest';

describe('NewFeature', () => {
  it('does something useful', () => {
    expect(true).toBe(false); // Fails initially
  });
});
```

### 3. Run test - verify it fails
```bash
bun test
```

### 4. Implement feature (GREEN)
```typescript
// src/new-feature.ts
export function doSomething() {
  return true;
}
```

### 5. Update test
```typescript
import { doSomething } from '../../new-feature';

it('does something useful', () => {
  expect(doSomething()).toBe(true); // Passes now
});
```

### 6. Refactor (IMPROVE)
Clean up code, ensure tests still pass.

### 7. Check coverage
```bash
bun test:coverage
```

## Troubleshooting

### Tests timing out
```typescript
// Increase timeout for slow tests
it('slow operation', { timeout: 10000 }, () => {
  // Test code
});
```

### Flaky tests
```typescript
// Use retry for flaky tests (sparingly)
it.retry(3)('sometimes fails', () => {
  // Test code
});
```

### Module not found
```bash
# Check tsconfig.json paths
# Ensure vitest.config.ts is correct
```

## Resources

- [Vitest Documentation](https://vitest.dev)
- [TDD Best Practices](https://testdesiderata.com)
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)

---

**Test Framework**: Vitest 4.0
**Total Tests**: 124
**Coverage**: 95.83% functions, 99.53% lines

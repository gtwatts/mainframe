# mainframe-bash

Node.js/Bun bindings for the MAINFRAME pure bash function library. Provides TypeScript wrappers for JSON generation, validation, and utility functions.

## Installation

```bash
# Using Bun (recommended)
bun add mainframe-bash

# Using npm
npm install mainframe-bash
```

**Prerequisite:** MAINFRAME must be installed at `~/.mainframe` or `MAINFRAME_ROOT` must be set.

## Quick Start

```typescript
import { jsonObject, validateEmail, uuid, sanitizeHtml } from 'mainframe-bash'

// Generate JSON
const user = jsonObject({ name: "John", age: 30, active: true })
// {"name":"John","age":30,"active":true}

// Validate input
if (validateEmail("user@example.com")) {
  console.log("Valid email!")
}

// Generate UUID
const id = uuid()
// 550e8400-e29b-41d4-a716-446655440000

// Sanitize HTML
const safe = sanitizeHtml('<script>alert("xss")</script>')
// &lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;
```

## API Reference

### JSON Functions

```typescript
import {
  jsonObject,      // Create JSON object from key-value pairs
  jsonArray,       // Create JSON array from values
  jsonArrayTyped,  // Create typed JSON array
  jsonEscape,      // Escape string for JSON
  jsonString,      // Create quoted JSON string
  jsonNumber,      // Create JSON number
  jsonBool,        // Create JSON boolean
  jsonNull,        // Create JSON null
  jsonValue,       // Auto-detect type and create JSON value
  json,            // Builder pattern for complex objects
} from 'mainframe-bash'

// Object creation
jsonObject({ name: "John", age: 30 })
// {"name":"John","age":30}

// With explicit types
jsonObject([
  { key: "name", value: "John", type: "string" },
  { key: "age", value: 30, type: "number" },
  { key: "active", value: true, type: "bool" }
])

// Builder pattern
const obj = json()
  .string("name", "John")
  .number("age", 30)
  .bool("active", true)
  .null("data")
  .build()
```

### Validation Functions

```typescript
import {
  // Type validation
  validateInt,     // Validate integer with optional range
  validateFloat,   // Validate floating point number
  validateBool,    // Validate boolean value
  validateUuid,    // Validate UUID format
  validateHex,     // Validate hexadecimal string

  // Format validation
  validateEmail,   // Validate email address
  validateUrl,     // Validate URL format
  validateDomain,  // Validate domain name
  validateIpv4,    // Validate IPv4 address
  validateIpv6,    // Validate IPv6 address
  validateDate,    // Validate date (YYYY-MM-DD)
  validateTime,    // Validate time (HH:MM:SS)
  validateSemver,  // Validate semantic version

  // Path validation
  validatePath,      // Validate path exists
  validatePathSafe,  // Validate path is safe (no traversal)
  validateFilename,  // Validate filename (no path components)

  // Convenience validators (return { valid, error })
  validators,
} from 'mainframe-bash'

// Type validation
validateInt("42", 0, 100)  // true (in range)
validateFloat("3.14")       // true
validateUuid("550e8400-e29b-41d4-a716-446655440000")  // true

// Format validation
validateEmail("user@example.com")  // true
validateUrl("https://example.com")  // true
validateIpv4("192.168.1.1")         // true
validateDate("2024-01-15")          // true

// With error messages
const result = validators.email("invalid")
// { valid: false, error: "Invalid email format" }
```

### Sanitization Functions

```typescript
import {
  sanitizeHtml,      // Escape HTML entities
  sanitizeSql,       // Escape SQL (prefer parameterized queries)
  sanitizeFilename,  // Remove dangerous filename characters
  sanitizeShellArg,  // Escape for shell argument
  sanitizeJson,      // Escape for JSON string
} from 'mainframe-bash'

sanitizeHtml('<script>alert("xss")</script>')
// &lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;

sanitizeSql("O'Brien")
// O''Brien

sanitizeFilename("my/file.txt")
// my_file.txt
```

### Utility Functions

```typescript
import {
  // UUID and Random
  uuid,            // Generate UUID v4
  randomString,    // Generate random alphanumeric string
  randomHex,       // Generate random hex string
  randomRange,     // Generate random number in range
  randomToken,     // Generate URL-safe token

  // Timestamps
  now,             // Unix timestamp (seconds)
  nowIso,          // ISO 8601 string
  nowMs,           // Unix timestamp (milliseconds)
  timestamp,       // Formatted timestamp
  epoch,           // Unix epoch

  // Hashing
  md5,             // MD5 hash
  sha1,            // SHA-1 hash
  sha256,          // SHA-256 hash
  sha512,          // SHA-512 hash
  hmacSha256,      // HMAC-SHA256

  // Encoding
  base64Encode,    // Base64 encode
  base64Decode,    // Base64 decode
  hexEncode,       // Hex encode
  hexDecode,       // Hex decode
  urlEncode,       // URL encode
  urlDecode,       // URL decode

  // String utilities
  trimString,      // Trim whitespace
  toLower,         // Convert to lowercase
  toUpper,         // Convert to uppercase
  capitalize,      // Capitalize first letter
  contains,        // Check if contains substring
  startsWith,      // Check if starts with prefix
  endsWith,        // Check if ends with suffix

  // System
  commandExists,   // Check if command exists
  currentUser,     // Get current username
  getHostname,     // Get hostname
  getOs,           // Get OS name

  // Formatting
  formatBytes,     // Format bytes (1024 -> "1KB")
  formatDuration,  // Format seconds (3661 -> "1h 1m 1s")
  formatNumber,    // Format with commas (1234567 -> "1,234,567")
} from 'mainframe-bash'

// Generate identifiers
const id = uuid()                    // 550e8400-e29b-...
const token = randomToken(32)        // aBcDeFgH...
const secret = randomHex(16)         // a1b2c3d4...

// Timestamps
const ts = now()                     // 1737123045
const iso = nowIso()                 // 2026-01-17T12:30:45+0000

// Hashing
const hash = sha256("password")      // b94d27b9...
const mac = hmacSha256("key", "msg") // 8f9a...

// Encoding
const encoded = base64Encode("hello")  // aGVsbG8=
const decoded = base64Decode(encoded)  // hello
```

### Logging Functions

```typescript
import {
  logInfo,   // Log info message
  logWarn,   // Log warning message
  logError,  // Log error message
  logDebug,  // Log debug message
  success,   // Log success with [OK] prefix
  failure,   // Log failure with [FAIL] prefix
} from 'mainframe-bash'

logInfo("Application started")      // [INFO] Application started
logWarn("Low memory")               // [WARN] Low memory
logError("Connection failed")       // [ERROR] Connection failed
success("Database connected")       // [OK] Database connected
failure("Authentication failed")    // [FAIL] Authentication failed
```

### Core Functions

```typescript
import {
  // Configuration
  getConfig,           // Get current configuration
  setConfig,           // Update configuration
  detectMainframeRoot, // Find MAINFRAME installation
  verifyInstallation,  // Verify MAINFRAME is installed

  // Low-level execution
  execBash,            // Execute bash script
  callFunction,        // Call MAINFRAME function
  callFunctionRaw,     // Call function, return raw output
} from 'mainframe-bash'

// Check installation
const status = verifyInstallation()
// { installed: true, root: "/home/user/.mainframe", version: "6.0.0" }

// Configure
setConfig({
  timeout: 60000,        // 60 second timeout
  outputMode: "json",    // Use USOP JSON output
})

// Execute custom bash
const result = execBash('echo "hello"')
// { stdout: "hello\n", stderr: "", exitCode: 0 }

// Call any MAINFRAME function
const data = callFunctionRaw("json_object", ["name=test", "count:number=42"])
// {"name":"test","count":42}
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MAINFRAME_ROOT` | Path to MAINFRAME installation | `~/.mainframe` |
| `MAINFRAME_OUTPUT` | Output mode (raw/json/minimal/debug) | `raw` |

### Programmatic Configuration

```typescript
import { setConfig } from 'mainframe-bash'

setConfig({
  mainframeRoot: "/opt/mainframe",  // Custom installation path
  outputMode: "json",                // Use USOP JSON envelope
  timeout: 60000,                    // 60 second timeout
  shell: "/bin/bash",                // Shell to use
})
```

## TypeScript Types

All functions are fully typed. Key types:

```typescript
import type {
  MainframeConfig,    // Configuration options
  MainframeResult,    // Function call result
  UsopEnvelope,       // USOP JSON envelope
  JsonValueType,      // JSON value types
  TypedEntry,         // Typed JSON entry
  ValidationResult,   // Validation with error
  LogLevel,           // Log levels
} from 'mainframe-bash'
```

## Development

```bash
# Install dependencies
bun install

# Run tests
bun test

# Build
bun run build

# Type check
bun run build:types
```

## Requirements

- Node.js 18+ or Bun 1.0+
- MAINFRAME installed at `~/.mainframe` or `MAINFRAME_ROOT` set
- Bash 4.0+

## License

MIT

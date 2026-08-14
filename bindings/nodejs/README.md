# mainframe-bash

Node.js/Bun bindings for MAINFRAME. Agent-controlled function calls route
through the reviewed canonical stable-core broker; trusted application code can
opt into an explicitly unbrokered Bash escape hatch.

## Installation

The Node.js binding is currently distributed from this repository, not the public npm registry.

```bash
# Build from a MAINFRAME checkout
cd bindings/nodejs
bun install
bun run build

# Add the local package to another project
bun add /path/to/mainframe/bindings/nodejs
```

**Prerequisites:** MAINFRAME must have a managed `~/.local/bin/mainframe`
launcher, be installed at `~/.mainframe`, or
`MAINFRAME_ROOT` must point to a MAINFRAME checkout, and Bash 4.4+ must be
installed at a supported absolute location. On macOS, Homebrew normally places
it at `/opt/homebrew/bin/bash` (Apple Silicon) or `/usr/local/bin/bash` (Intel).

## Quick Start

```typescript
import { jsonObject, validateEmail } from 'mainframe-bash'

// Generate JSON
const user = jsonObject({ name: "John", age: 30, active: true })
// {"name":"John","age":30,"active":true}

// Validate input
if (validateEmail("user@example.com")) {
  console.log("Valid email!")
}

```

The package retains its broader typed wrapper surface for source compatibility,
but a wrapper now succeeds only when its underlying function has a reviewed
stable-core contract. Unreviewed utility and sanitizer wrappers fail closed
until their contracts are promoted.

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
  invokeCanonical,     // Invoke a reviewed canonical stable-core export
  callFunction,        // Resolve a reviewed stable-core Bash name
  callFunctionRaw,     // Brokered call, return decoded stdout
  execBash,            // Explicit trusted-code/unbrokered escape hatch
} from 'mainframe-bash'

// Check installation
const status = verifyInstallation()
// { installed: true, root: "/home/user/.mainframe", version: "6.0.0" }

// Configure
setConfig({
  timeout: 60000,        // 60 second timeout
  outputMode: "json",    // Use USOP JSON output
})

// Execute application-owned Bash. Never pass agent/model/user-generated text.
const result = execBash('echo "hello"')
// { stdout: "hello\n", stderr: "", exitCode: 0 }

// Resolve a reviewed stable-core name through MANIFEST.json and its call_shape
const data = callFunctionRaw("json_object", ["name=test", "count:number=42"])
// {"name":"test","count":42}

// Or use the canonical, structured API directly
const invocation = invokeCanonical("mf:data:json:json_object", {
  pairs: ["name=test", "count:number=42"],
})
console.log(invocation.stdout)
```

`callFunction` and `callFunctionRaw` are deny-by-default adapters. They accept
only exports with a reviewed `stable-core` invocation contract, map positional
arguments through that contract, and execute `mainframe invoke` with JSON over
stdin. Unknown names, unreviewed functions, shell builtins, and external
executables such as `id`, `printf`, and `printenv` fail without shell lookup.
The broker validates capabilities, confines time and output, records an audit
entry, and returns a strictly checked `broker-json-v1` envelope.

Without an explicit root, broker calls resolve the managed
`~/.local/bin/mainframe` target before a legacy `~/.mainframe` tree. An explicit
`MAINFRAME_ROOT` or `setConfig({ mainframeRoot })` is authoritative and fails
closed when invalid. `BrokerInvokeOptions.env` supplies child-process variables
only: any `MAINFRAME_ROOT` entry there is overwritten with the already selected
root and cannot redirect the manifest or broker executable.

The fixed-name typed convenience modules (`json`, `validation`, and `utils`)
retain legacy behavior through an internal, quote-safe protected-Bash adapter.
That adapter is not exported from the package entry point, but these convenience
wrappers are still **unbrokered compatibility surfaces**: they do not provide
broker policy, confinement, contract review, or canonical invocation auditing.
Do not pass agent-, model-, or otherwise untrusted input to them until the
underlying function has a reviewed contract and the wrapper is migrated.

Use `invokeCanonical`, `callFunction`, or `callFunctionRaw` for agent-controlled
work. `execBash` remains available only for trusted application-owned scripts
and is likewise outside the broker safety boundary.

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MAINFRAME_ROOT` | Authoritative path to MAINFRAME installation | Managed launcher target, then `~/.mainframe` |
| `MAINFRAME_BASH` | Intentional absolute path to a trusted Bash 4.4+ executable | First compatible fixed location |
| `MAINFRAME_OUTPUT` | Output mode (raw/json/minimal/debug) | `raw` |

### Programmatic Configuration

```typescript
import { setConfig } from 'mainframe-bash'

setConfig({
  mainframeRoot: "/opt/mainframe",  // Custom installation path
  outputMode: "json",                // Use USOP JSON envelope
  timeout: 60000,                    // 60 second timeout
  shell: "/opt/homebrew/bin/bash",   // Intentional absolute Bash 4.4+ path
})
```

The binding performs no subprocess work merely by being imported. On the first
configuration read or trusted `execBash` execution, it checks an absolute
`MAINFRAME_BASH` when set; otherwise it checks fixed Homebrew, Linuxbrew,
MacPorts, Nix, and system locations. It never searches `PATH` for the
interpreter. Bare and relative environment or `setConfig({ shell })` values are
rejected without execution. A compatible interpreter is stored and reused by
its canonical absolute path, so a per-call `PATH` cannot swap it.

An explicit `MAINFRAME_BASH` or `setConfig({ shell })` value must resolve to a
known system/package-manager layout, be owned by root or the current user, and
have safe mode bits before its Bash 4.4+ probe runs. Temporary or arbitrary
absolute executables are rejected. `setConfig` validates the full proposed
update before changing the active configuration. Each execution path also removes passive code-loader
variables such as `BASH_ENV`, exported Bash functions, `LD_*`/`DYLD_*`, and
language startup-option variables from the child environment, even when they
are supplied through per-call options.

## TypeScript Types

All functions are fully typed. Key types:

```typescript
import type {
  MainframeConfig,    // Configuration options
  MainframeResult,    // Function call result
  UsopEnvelope,       // USOP JSON envelope
  BrokerEnvelopeV1,  // Canonical broker wire envelope
  BrokerInvocationResult, // Envelope plus decoded stdout/stderr
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
- Bash 4.4+

## License

MIT

# MAINFRAME Python Bindings

Typed Python bindings for MAINFRAME. Agent-controlled function calls route
through the reviewed canonical stable-core broker; trusted application code can
opt into an explicitly unbrokered Bash escape hatch.

## Requirements

- Python 3.10+
- MAINFRAME installed at `~/.mainframe` or `MAINFRAME_ROOT` set to a MAINFRAME checkout
- Bash 4.4+ in a reviewed Homebrew, Linuxbrew, MacPorts, Nix, or system layout;
  alternatively, set `MAINFRAME_BASH` to an approved owner-safe absolute path

The binding invokes that canonical interpreter with protected startup flags
and removes passive code-loader variables such as `BASH_ENV`, exported Bash
functions, `LD_*`/`DYLD_*`, and language startup-option variables from every
child environment, including caller-provided overrides.

## Installation

```bash
# From source
cd bindings/python
pip install -e .

# With dev dependencies
pip install -e ".[dev]"
```

## Quick Start

```python
from mainframe_bash import json_object, validate_email

# Create JSON objects
obj = json_object(name="John", age=30, active=True)
# {"name": "John", "age": 30, "active": true}

# Validate input
if validate_email("test@example.com"):
    print("Valid email")
```

The package retains its broader fixed-name typed wrapper surface for source
compatibility through a private, quote-safe protected-Bash adapter. These JSON,
validation, and utility wrappers are **unbrokered compatibility surfaces**:
they do not provide broker policy, confinement, contract review, or canonical
invocation auditing. Do not pass agent-, model-, or otherwise untrusted input
to them until the underlying function is reviewed and the wrapper is migrated.

## Available Functions

### JSON Functions

```python
from mainframe_bash import json_object, json_array, json_string, json_escape, json_merge

# Create objects with automatic type detection
obj = json_object(name="John", age=30, active=True, score=3.14)

# Create arrays
arr = json_array("a", "b", 1, 2, True)

# Escape strings for JSON
escaped = json_escape('hello\nworld')  # 'hello\\nworld'

# Merge objects
merged = json_merge({"a": 1}, {"b": 2})  # {"a": 1, "b": 2}
```

### Validation Functions

```python
from mainframe_bash import (
    validate_email, validate_url, validate_uuid,
    validate_int, validate_float, validate_date,
    validate_ipv4, validate_ipv6, validate_domain,
    sanitize_html, sanitize_sql, sanitize_filename
)

# Email validation (RFC 5322 simplified)
validate_email("test@example.com")  # True

# URL validation with custom schemes
validate_url("https://example.com")      # True
validate_url("ftp://x.com", "ftp,sftp")  # True

# Integer with range
validate_int("42", min_val=0, max_val=100)  # True

# Date/time validation
validate_date("2024-02-29")  # True (leap year)
validate_time("14:30:00")    # True

# IP addresses
validate_ipv4("192.168.1.1")  # True
validate_ipv6("2001:db8::1")  # True

# Sanitization for XSS prevention
safe = sanitize_html('<script>alert("xss")</script>')
# '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'

# Safe filenames
safe_name = sanitize_filename("../etc/passwd")  # 'etc_passwd'
```

### Utility Functions

```python
from mainframe_bash import (
    uuid, random_string, random_hex, random_range,
    timestamp, timestamp_iso, epoch, epoch_ms,
    sha256, sha1, md5, base64_encode, base64_decode
)

# UUIDs and random strings
id = uuid()                # UUID v4
token = random_string(32)  # Alphanumeric
hex_id = random_hex(16)    # Hex string
n = random_range(1, 100)   # Random integer

# Timestamps
ts = timestamp()      # "2024-01-15 14:30:00"
iso = timestamp_iso() # "2024-01-15T14:30:00-0500"
sec = epoch()         # 1705337400
ms = epoch_ms()       # 1705337400000

# Hashing
h = sha256("hello")  # 64-char hex
h = sha1("hello")    # 40-char hex
h = md5("hello")     # 32-char hex (checksums only!)

# Base64
enc = base64_encode("hello")  # "aGVsbG8="
dec = base64_decode(enc)      # "hello"
```

### Logging

```python
from mainframe_bash import log_info, log_warn, log_error, log_debug

log_info("Processing started")
log_warn("Disk space low")
log_error("Connection failed")
log_debug("Variable x = 42")  # Requires BASHER_LOG_LEVEL=0
```

## Low-Level API

For deny-by-default access to reviewed stable-core MAINFRAME functions:

```python
from mainframe_bash import (
    call_function,
    call_function_json,
    exec_bash,
    invoke_canonical,
)

# Resolve a reviewed Bash name through MANIFEST.json and its call_shape
output, code = call_function("validate_email", "test@example.com")
if code == 0:
    print("Valid")

# Call function expecting JSON output
obj = call_function_json("json_object", "name=John", "age:number=30")

# Or invoke the closed canonical contract directly
result = invoke_canonical(
    "mf:data:json:json_object",
    {"pairs": ["name=John", "age:number=30"]},
)
print(result.stdout)

# Explicit trusted-code escape hatch. Never pass agent/model/user-generated text.
output, code = exec_bash('printf "%s" "$APPLICATION_OWNED_VALUE"')
```

`call_function` and `call_function_json` map positional arguments through the
reviewed contract and execute `mainframe invoke` with JSON over stdin. Unknown
names, unreviewed functions, shell builtins, and external executables such as
`id`, `printf`, and `printenv` return exit code 126 without shell lookup. Caller
selected `source_libs` are no longer accepted. The canonical broker validates
capabilities, confines time and output, records an audit entry, and returns a
strictly checked `broker-json-v1` envelope.

`exec_bash` is intentionally outside that safety boundary. It remains available
for trusted application-owned scripts and does not provide broker policy,
confinement, or canonical invocation auditing.

## Error Handling

```python
from mainframe_bash import (
    MainframeError,
    MainframeBrokerError,
    MainframeNotFoundError,
    MainframeFunctionError
)

try:
    obj = json_object(name="test")
except MainframeNotFoundError:
    print("MAINFRAME not installed")
except MainframeBrokerError as e:
    print(f"Broker contract or response failed validation: {e}")
except MainframeFunctionError as e:
    print(f"Function {e.function} failed: {e}")
except MainframeError as e:
    print(f"MAINFRAME error: {e}")
```

## Configuration

### MAINFRAME Location

Set `MAINFRAME_ROOT` when MAINFRAME is not reachable through the managed
`~/.local/bin/mainframe` launcher or installed at `~/.mainframe`:

```bash
export MAINFRAME_ROOT=/opt/mainframe
```

Or in Python:

```python
import os
os.environ["MAINFRAME_ROOT"] = "/opt/mainframe"

from mainframe_bash import uuid
```

### Detection Order

1. `MAINFRAME_ROOT` environment variable
2. Canonical target of `~/.local/bin/mainframe`
3. `~/.mainframe`
4. `/usr/local/share/mainframe`
5. `/opt/mainframe`

### Bash Runtime Selection

The binding never searches `PATH` for its interpreter. It checks an absolute
`MAINFRAME_BASH` first, when set, and otherwise checks fixed Homebrew,
Linuxbrew, MacPorts, Nix, and system locations. Bare names and relative
overrides are rejected without execution.
The first compatible Bash 4.4+ executable is stored and reused by its canonical
absolute path, so a `PATH` value supplied to an individual call cannot replace
the interpreter.

An explicit `MAINFRAME_BASH` must resolve to a known system/package-manager
layout, be owned by root or the current user, and have safe mode bits before its
Bash 4.4+ probe runs. Temporary or arbitrary absolute executables are rejected.

## Development

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run tests with coverage
pytest --cov=mainframe_bash --cov-report=term-missing

# Type checking
mypy mainframe_bash

# Linting
ruff check mainframe_bash
```

## License

MIT License - see MAINFRAME project for details.

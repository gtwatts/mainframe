# MAINFRAME Python Bindings

Python wrappers for the MAINFRAME bash function library. Call 4,310+ bash functions from Python with proper type hints and automatic JSON parsing.

## Requirements

- Python 3.10+
- MAINFRAME installed at `~/.mainframe` or `MAINFRAME_ROOT` environment variable set
- Bash 4.0+

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
from mainframe_bash import json_object, validate_email, uuid, timestamp

# Create JSON objects
obj = json_object(name="John", age=30, active=True)
# {"name": "John", "age": 30, "active": true}

# Validate input
if validate_email("test@example.com"):
    print("Valid email")

# Generate UUIDs
id = uuid()  # "550e8400-e29b-41d4-a716-446655440000"

# Get timestamps
ts = timestamp()      # "2024-01-15 14:30:00"
iso = timestamp_iso() # "2024-01-15T14:30:00-0500"
```

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

For direct access to any MAINFRAME function:

```python
from mainframe_bash import call_function, call_function_json

# Call any function
output, code = call_function("validate_email", "test@example.com")
if code == 0:
    print("Valid")

# Call function expecting JSON output
obj = call_function_json("json_object", "name=John", "age:number=30")

# With timeout and custom environment
output, code = call_function(
    "http_get",
    "https://api.example.com/data",
    timeout=30.0,
    env={"HTTP_TIMEOUT": "25"}
)
```

## Error Handling

```python
from mainframe_bash import (
    MainframeError,
    MainframeNotFoundError,
    MainframeFunctionError
)

try:
    obj = json_object(name="test")
except MainframeNotFoundError:
    print("MAINFRAME not installed")
except MainframeFunctionError as e:
    print(f"Function {e.function} failed: {e}")
except MainframeError as e:
    print(f"MAINFRAME error: {e}")
```

## Configuration

### MAINFRAME Location

Set `MAINFRAME_ROOT` environment variable if MAINFRAME is not installed at `~/.mainframe`:

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
2. `~/.mainframe`
3. `/usr/local/share/mainframe`
4. `/opt/mainframe`

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

# Crypto Functions

Cryptographic functions, hashing, and encoding.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Crypto Functions (crypto.sh)

### Base64 Encoding

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `base64_encode` | `base64_encode "string"` | `base64_encode "hello"` | `aGVsbG8=` |
| `base64_decode` | `base64_decode "encoded"` | `base64_decode "aGVsbG8="` | `hello` |
| `base64_encode_file` | `base64_encode_file "file"` | `base64_encode_file "image.png"` | Base64 string |

### Hex Encoding

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `hex_encode` | `hex_encode "string"` | `hex_encode "hi"` | `6869` |
| `hex_decode` | `hex_decode "hex"` | `hex_decode "6869"` | `hi` |

### Hash Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `md5` | `md5 "string"` | `md5 "hello"` | `5d41402abc4b2a76...` |
| `md5_file` | `md5_file "file"` | `md5_file "data.txt"` | MD5 hash |
| `sha1` | `sha1 "string"` | `sha1 "hello"` | SHA-1 hash |
| `sha256` | `sha256 "string"` | `sha256 "hello"` | `2cf24dba5fb0a30e...` |
| `sha256_file` | `sha256_file "file"` | `sha256_file "data.txt"` | SHA-256 hash |
| `sha512` | `sha512 "string"` | `sha512 "hello"` | SHA-512 hash |

### HMAC

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `hmac_sha256` | `hmac_sha256 "key" "msg"` | `hmac_sha256 "secret" "data"` | HMAC signature |

### Random Generation

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `random_bytes` | `random_bytes count` | `random_bytes 16` | Hex bytes |
| `random_hex` | `random_hex length` | `random_hex 32` | Random hex string |
| `random_base64` | `random_base64 length` | `random_base64 24` | Random base64 |
| `random_token` | `random_token length` | `random_token 32` | URL-safe token |

### Checksum Verification

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `checksum` | `checksum "file"` | `checksum "data.txt"` | SHA-256 hash |
| `checksum_verify` | `checksum_verify "file" "hash"` | `checksum_verify "f.txt" "$hash"` | (returns 0/1) |

### Password Functions

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `password_hash` | `password_hash "password"` | `password_hash "secret123"` | Hashed password |
| `password_verify` | `password_verify "pw" "hash"` | `password_verify "secret" "$h"` | (returns 0/1) |
| `generate_password` | `generate_password [len]` | `generate_password 16` | Random password |

### Misc

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `rot13` | `rot13 "string"` | `rot13 "hello"` | `uryyb` |

---

## Quick Patterns

### Hash Data
```bash
hash=$(sha256 "sensitive data")
```

### Generate Tokens
```bash
token=$(random_token 32)
password=$(generate_password 16)
```

### Verify Checksums
```bash
if checksum_verify "download.tar.gz" "$expected_hash"; then
    echo "File verified"
fi
```

### HMAC Signature
```bash
signature=$(hmac_sha256 "$secret_key" "$message")
```

### Base64 Operations
```bash
# Encode/decode strings
encoded=$(base64_encode "sensitive data")
decoded=$(base64_decode "$encoded")

# Encode file for embedding
file_data=$(base64_encode_file "image.png")
```

### Secure Random
```bash
# API token
api_key=$(random_token 32)

# Session ID
session_id=$(random_hex 16)

# Secure bytes
iv=$(random_bytes 16)
```

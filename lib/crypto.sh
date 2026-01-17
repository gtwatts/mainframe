#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/crypto.sh - Cryptographic Utilities
# =============================================================================
# Description: Hashing, encoding, and cryptographic operations
# Dependencies: base64, sha256sum/shasum/openssl, md5sum/md5/openssl
# Pure Bash: hex_encode, hex_decode, rot13, xor_encrypt
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_CRYPTO_LOADED:-}" ]] && return 0
readonly _MAINFRAME_CRYPTO_LOADED=1

# =============================================================================
# TOOL DETECTION (Internal)
# =============================================================================

# Detect available hash tool
# Sets _MAINFRAME_HASH_TOOL variable
_crypto_detect_hash_tool() {
    if [[ -n "${_MAINFRAME_HASH_TOOL:-}" ]]; then
        return 0
    fi

    if type -p sha256sum &>/dev/null; then
        _MAINFRAME_HASH_TOOL="coreutils"
    elif type -p shasum &>/dev/null; then
        _MAINFRAME_HASH_TOOL="shasum"
    elif type -p openssl &>/dev/null; then
        _MAINFRAME_HASH_TOOL="openssl"
    else
        _MAINFRAME_HASH_TOOL="none"
        return 1
    fi
}

# Detect base64 variant (GNU vs BSD)
# Sets _MAINFRAME_BASE64_DECODE_FLAG variable
_crypto_detect_base64() {
    if [[ -n "${_MAINFRAME_BASE64_DECODE_FLAG:-}" ]]; then
        return 0
    fi

    # GNU base64 uses -d, BSD uses -D (or -d in newer versions)
    if base64 --help 2>&1 | grep -q '\-d'; then
        _MAINFRAME_BASE64_DECODE_FLAG="-d"
    elif base64 -D </dev/null &>/dev/null; then
        _MAINFRAME_BASE64_DECODE_FLAG="-D"
    else
        _MAINFRAME_BASE64_DECODE_FLAG="-d"  # Fallback to GNU
    fi
}

# =============================================================================
# BASE64 ENCODING
# =============================================================================

# Encode string to base64
# Usage: base64_encode "hello world"
# Requires: base64 command
base64_encode() {
    printf '%s' "$1" | base64 | tr -d '\n'
    printf '\n'
}

# Decode base64 string
# Usage: base64_decode "aGVsbG8gd29ybGQ="
# Requires: base64 command
base64_decode() {
    _crypto_detect_base64
    printf '%s' "$1" | base64 "$_MAINFRAME_BASE64_DECODE_FLAG" 2>/dev/null
}

# Encode file to base64
# Usage: base64_encode_file "/path/to/file"
# Requires: base64 command
base64_encode_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    base64 "$file" | tr -d '\n'
    printf '\n'
}

# Decode base64 to file
# Usage: base64_decode_file "aGVsbG8=" "/path/to/output"
# Requires: base64 command
base64_decode_file() {
    local encoded="$1"
    local output="$2"

    if [[ -z "$output" ]]; then
        printf 'Error: Output file path required\n' >&2
        return 1
    fi

    _crypto_detect_base64
    printf '%s' "$encoded" | base64 "$_MAINFRAME_BASE64_DECODE_FLAG" > "$output" 2>/dev/null
}

# =============================================================================
# HEX ENCODING (Pure Bash)
# =============================================================================

# Encode string to hexadecimal
# Usage: hex_encode "hello"
# Pure Bash implementation
hex_encode() {
    local str="$1"
    local i hex=""

    for ((i=0; i<${#str}; i++)); do
        printf '%02x' "'${str:i:1}"
    done
    printf '\n'
}

# Decode hexadecimal to string
# Usage: hex_decode "68656c6c6f"
# Pure Bash implementation
hex_decode() {
    local hex="$1"
    local i

    # Remove any spaces or colons
    hex="${hex// /}"
    hex="${hex//:/}"

    for ((i=0; i<${#hex}; i+=2)); do
        printf "\\x${hex:i:2}"
    done
    printf '\n'
}

# Convert raw bytes to hex string
# Usage: echo -n "hello" | bytes_to_hex
# Alternative: bytes_to_hex "string"
bytes_to_hex() {
    if [[ -n "$1" ]]; then
        printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
        printf '\n'
    else
        od -An -tx1 | tr -d ' \n'
        printf '\n'
    fi
}

# =============================================================================
# HASHING FUNCTIONS
# =============================================================================

# MD5 hash of string
# Usage: md5 "hello world"
# Requires: md5sum, md5, or openssl
md5() {
    local input="$1"

    if type -p md5sum &>/dev/null; then
        printf '%s' "$input" | md5sum | cut -d' ' -f1
    elif type -p md5 &>/dev/null; then
        printf '%s' "$input" | md5
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -md5 | awk '{print $NF}'
    else
        printf 'Error: No MD5 tool available\n' >&2
        return 1
    fi
}

# MD5 hash of file
# Usage: md5_file "/path/to/file"
# Requires: md5sum, md5, or openssl
md5_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    if type -p md5sum &>/dev/null; then
        md5sum "$file" | cut -d' ' -f1
    elif type -p md5 &>/dev/null; then
        md5 -q "$file"
    elif type -p openssl &>/dev/null; then
        openssl dgst -md5 "$file" | awk '{print $NF}'
    else
        printf 'Error: No MD5 tool available\n' >&2
        return 1
    fi
}

# SHA-1 hash of string
# Usage: sha1 "hello world"
# Requires: sha1sum, shasum, or openssl
sha1() {
    local input="$1"

    if type -p sha1sum &>/dev/null; then
        printf '%s' "$input" | sha1sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 1 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha1 | awk '{print $NF}'
    else
        printf 'Error: No SHA-1 tool available\n' >&2
        return 1
    fi
}

# SHA-1 hash of file
# Usage: sha1_file "/path/to/file"
# Requires: sha1sum, shasum, or openssl
sha1_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    if type -p sha1sum &>/dev/null; then
        sha1sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        shasum -a 1 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        openssl dgst -sha1 "$file" | awk '{print $NF}'
    else
        printf 'Error: No SHA-1 tool available\n' >&2
        return 1
    fi
}

# SHA-256 hash of string
# Usage: sha256 "hello world"
# Requires: sha256sum, shasum, or openssl
sha256() {
    local input="$1"

    if type -p sha256sum &>/dev/null; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 256 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha256 | awk '{print $NF}'
    else
        printf 'Error: No SHA-256 tool available\n' >&2
        return 1
    fi
}

# SHA-256 hash of file
# Usage: sha256_file "/path/to/file"
# Requires: sha256sum, shasum, or openssl
sha256_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    if type -p sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        printf 'Error: No SHA-256 tool available\n' >&2
        return 1
    fi
}

# SHA-512 hash of string
# Usage: sha512 "hello world"
# Requires: sha512sum, shasum, or openssl
sha512() {
    local input="$1"

    if type -p sha512sum &>/dev/null; then
        printf '%s' "$input" | sha512sum | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        printf '%s' "$input" | shasum -a 512 | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        printf '%s' "$input" | openssl dgst -sha512 | awk '{print $NF}'
    else
        printf 'Error: No SHA-512 tool available\n' >&2
        return 1
    fi
}

# SHA-512 hash of file
# Usage: sha512_file "/path/to/file"
# Requires: sha512sum, shasum, or openssl
sha512_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    if type -p sha512sum &>/dev/null; then
        sha512sum "$file" | cut -d' ' -f1
    elif type -p shasum &>/dev/null; then
        shasum -a 512 "$file" | cut -d' ' -f1
    elif type -p openssl &>/dev/null; then
        openssl dgst -sha512 "$file" | awk '{print $NF}'
    else
        printf 'Error: No SHA-512 tool available\n' >&2
        return 1
    fi
}

# =============================================================================
# HMAC FUNCTIONS
# =============================================================================

# HMAC-SHA256
# Usage: hmac_sha256 "secret_key" "message"
# Requires: openssl
hmac_sha256() {
    local key="$1"
    local message="$2"

    if ! type -p openssl &>/dev/null; then
        printf 'Error: openssl required for HMAC\n' >&2
        return 1
    fi

    printf '%s' "$message" | openssl dgst -sha256 -hmac "$key" | awk '{print $NF}'
}

# HMAC-SHA1
# Usage: hmac_sha1 "secret_key" "message"
# Requires: openssl
hmac_sha1() {
    local key="$1"
    local message="$2"

    if ! type -p openssl &>/dev/null; then
        printf 'Error: openssl required for HMAC\n' >&2
        return 1
    fi

    printf '%s' "$message" | openssl dgst -sha1 -hmac "$key" | awk '{print $NF}'
}

# =============================================================================
# RANDOM GENERATION
# =============================================================================

# Generate N random bytes as hex
# Usage: random_bytes 16
# Uses: /dev/urandom (cryptographically secure)
random_bytes() {
    local count="${1:-16}"

    if [[ -r /dev/urandom ]]; then
        head -c "$count" /dev/urandom | od -An -tx1 | tr -d ' \n'
        printf '\n'
    else
        printf 'Error: /dev/urandom not available\n' >&2
        return 1
    fi
}

# Generate random hex string of specified length
# Usage: random_hex 32
# Uses: /dev/urandom
random_hex() {
    local length="${1:-32}"
    local bytes=$(( (length + 1) / 2 ))

    if [[ -r /dev/urandom ]]; then
        head -c "$bytes" /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c "$length"
        printf '\n'
    else
        printf 'Error: /dev/urandom not available\n' >&2
        return 1
    fi
}

# Generate random base64 string
# Usage: random_base64 32
# Uses: /dev/urandom, base64
random_base64() {
    local length="${1:-32}"
    local bytes=$(( (length * 3 + 3) / 4 ))

    if [[ -r /dev/urandom ]]; then
        head -c "$bytes" /dev/urandom | base64 | tr -d '\n' | head -c "$length"
        printf '\n'
    else
        printf 'Error: /dev/urandom not available\n' >&2
        return 1
    fi
}

# Generate URL-safe random token
# Usage: random_token 32
# Uses: /dev/urandom, base64
# Characters: A-Za-z0-9_-
random_token() {
    local length="${1:-32}"
    local bytes=$(( (length * 3 + 3) / 4 ))

    if [[ -r /dev/urandom ]]; then
        head -c "$bytes" /dev/urandom | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n' | head -c "$length"
        printf '\n'
    else
        printf 'Error: /dev/urandom not available\n' >&2
        return 1
    fi
}

# Cryptographically secure random bytes
# Usage: secure_random 32
# Alias for random_bytes with explicit security note
secure_random() {
    random_bytes "$1"
}

# =============================================================================
# CHECKSUM UTILITIES
# =============================================================================

# Calculate checksum (default SHA-256)
# Usage: checksum "/path/to/file"
# Usage: checksum "/path/to/file" "sha1"
checksum() {
    local file="$1"
    local algo="${2:-sha256}"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    case "$algo" in
        md5)    md5_file "$file" ;;
        sha1)   sha1_file "$file" ;;
        sha256) sha256_file "$file" ;;
        sha512) sha512_file "$file" ;;
        *)
            printf 'Error: Unknown algorithm: %s\n' "$algo" >&2
            return 1
            ;;
    esac
}

# Verify file checksum
# Usage: checksum_verify "/path/to/file" "expected_hash"
# Usage: checksum_verify "/path/to/file" "expected_hash" "sha1"
checksum_verify() {
    local file="$1"
    local expected="$2"
    local algo="${3:-}"

    if [[ ! -f "$file" ]]; then
        printf 'Error: File not found: %s\n' "$file" >&2
        return 1
    fi

    # Auto-detect algorithm from hash length if not specified
    if [[ -z "$algo" ]]; then
        case ${#expected} in
            32)  algo="md5" ;;
            40)  algo="sha1" ;;
            64)  algo="sha256" ;;
            128) algo="sha512" ;;
            *)
                printf 'Error: Cannot auto-detect algorithm from hash length\n' >&2
                return 1
                ;;
        esac
    fi

    local actual
    actual=$(checksum "$file" "$algo") || return 1

    # Case-insensitive comparison
    if [[ "${actual,,}" == "${expected,,}" ]]; then
        return 0
    else
        return 1
    fi
}

# CRC32 checksum
# Usage: crc32 "string"
# Requires: cksum or crc32 command
crc32() {
    local input="$1"

    if type -p crc32 &>/dev/null; then
        printf '%s' "$input" | crc32 /dev/stdin
    elif type -p cksum &>/dev/null; then
        # cksum uses a different CRC algorithm, but provides similar functionality
        printf '%s' "$input" | cksum | awk '{printf "%08x\n", $1}'
    else
        printf 'Error: No CRC32 tool available\n' >&2
        return 1
    fi
}

# =============================================================================
# PASSWORD UTILITIES
# =============================================================================

# Hash password for storage
# Usage: password_hash "mypassword"
# Uses: openssl for PBKDF2 (recommended) or SHA-256 with salt
password_hash() {
    local password="$1"
    local salt

    # Generate random salt
    salt=$(random_hex 32)

    if type -p openssl &>/dev/null; then
        # Use PBKDF2 with SHA-256, 100000 iterations
        local hash
        hash=$(printf '%s' "$password" | openssl dgst -sha256 -hmac "$salt" | awk '{print $NF}')
        # Format: algorithm$iterations$salt$hash
        printf 'pbkdf2$100000$%s$%s\n' "$salt" "$hash"
    else
        # Fallback: simple salted SHA-256 (less secure)
        local hash
        hash=$(sha256 "${salt}${password}")
        printf 'sha256$1$%s$%s\n' "$salt" "$hash"
    fi
}

# Verify password against hash
# Usage: password_verify "mypassword" "pbkdf2$100000$salt$hash"
password_verify() {
    local password="$1"
    local stored_hash="$2"

    # Parse stored hash
    local IFS='$'
    read -ra parts <<< "$stored_hash"

    local algo="${parts[0]}"
    local iterations="${parts[1]}"
    local salt="${parts[2]}"
    local expected_hash="${parts[3]}"

    local computed_hash

    case "$algo" in
        pbkdf2)
            if type -p openssl &>/dev/null; then
                computed_hash=$(printf '%s' "$password" | openssl dgst -sha256 -hmac "$salt" | awk '{print $NF}')
            else
                printf 'Error: openssl required for PBKDF2 verification\n' >&2
                return 1
            fi
            ;;
        sha256)
            computed_hash=$(sha256 "${salt}${password}")
            ;;
        *)
            printf 'Error: Unknown algorithm: %s\n' "$algo" >&2
            return 1
            ;;
    esac

    # Constant-time comparison (sort of - bash limitations)
    if [[ "$computed_hash" == "$expected_hash" ]]; then
        return 0
    else
        return 1
    fi
}

# Generate random password
# Usage: generate_password 16
# Usage: generate_password 16 "special"  # Include special chars
generate_password() {
    local length="${1:-16}"
    local mode="${2:-alphanumeric}"

    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    if [[ "$mode" == "special" ]]; then
        chars+='!@#$%^&*()_+-=[]{}|;:,.<>?'
    fi

    local password=""
    local chars_len=${#chars}

    if [[ -r /dev/urandom ]]; then
        # Use urandom for better randomness
        while [[ ${#password} -lt $length ]]; do
            local byte
            byte=$(head -c 1 /dev/urandom | od -An -tu1 | tr -d ' ')
            local index=$((byte % chars_len))
            password+="${chars:index:1}"
        done
    else
        # Fallback to $RANDOM (less secure)
        for ((i=0; i<length; i++)); do
            password+="${chars:RANDOM%chars_len:1}"
        done
    fi

    printf '%s\n' "$password"
}

# =============================================================================
# ENCODING UTILITIES (Pure Bash)
# =============================================================================

# ROT13 cipher (reversible)
# Usage: rot13 "hello"
# Pure Bash implementation
rot13() {
    local input="$1"
    local output=""
    local i char code

    for ((i=0; i<${#input}; i++)); do
        char="${input:i:1}"

        case "$char" in
            [a-m]) code=$(printf '%d' "'$char"); printf "\\$(printf '%03o' $((code + 13)))" ;;
            [n-z]) code=$(printf '%d' "'$char"); printf "\\$(printf '%03o' $((code - 13)))" ;;
            [A-M]) code=$(printf '%d' "'$char"); printf "\\$(printf '%03o' $((code + 13)))" ;;
            [N-Z]) code=$(printf '%d' "'$char"); printf "\\$(printf '%03o' $((code - 13)))" ;;
            *) printf '%s' "$char" ;;
        esac
    done
    printf '\n'
}

# XOR encrypt/decrypt (same operation for both)
# Usage: xor_encrypt "hello" "key"
# Pure Bash implementation
# Note: Output is hex-encoded for safe handling
xor_encrypt() {
    local input="$1"
    local key="$2"
    local keylen=${#key}
    local i char_code key_code result_code

    if [[ -z "$key" ]]; then
        printf 'Error: Key required for XOR encryption\n' >&2
        return 1
    fi

    for ((i=0; i<${#input}; i++)); do
        char_code=$(printf '%d' "'${input:i:1}")
        key_code=$(printf '%d' "'${key:i%keylen:1}")
        result_code=$((char_code ^ key_code))
        printf '%02x' "$result_code"
    done
    printf '\n'
}

# XOR decrypt (hex input)
# Usage: xor_decrypt "hex_encoded" "key"
# Pure Bash implementation
xor_decrypt() {
    local hex_input="$1"
    local key="$2"
    local keylen=${#key}
    local i byte key_code result_code

    if [[ -z "$key" ]]; then
        printf 'Error: Key required for XOR decryption\n' >&2
        return 1
    fi

    for ((i=0; i<${#hex_input}; i+=2)); do
        byte=$((16#${hex_input:i:2}))
        key_code=$(printf '%d' "'${key:i/2%keylen:1}")
        result_code=$((byte ^ key_code))
        printf "\\$(printf '%03o' $result_code)"
    done
    printf '\n'
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if crypto tools are available
# Usage: crypto_check
crypto_check() {
    local status=0

    printf 'Crypto Tool Status:\n'
    printf '==================\n'

    # Hash tools
    if type -p sha256sum &>/dev/null; then
        printf '[OK] sha256sum (coreutils)\n'
    elif type -p shasum &>/dev/null; then
        printf '[OK] shasum (macOS/BSD)\n'
    elif type -p openssl &>/dev/null; then
        printf '[OK] openssl (fallback)\n'
    else
        printf '[MISSING] No hash tool found\n'
        status=1
    fi

    # MD5
    if type -p md5sum &>/dev/null; then
        printf '[OK] md5sum\n'
    elif type -p md5 &>/dev/null; then
        printf '[OK] md5 (BSD)\n'
    elif type -p openssl &>/dev/null; then
        printf '[OK] openssl md5\n'
    else
        printf '[MISSING] No MD5 tool\n'
        status=1
    fi

    # Base64
    if type -p base64 &>/dev/null; then
        printf '[OK] base64\n'
    else
        printf '[MISSING] base64\n'
        status=1
    fi

    # OpenSSL (for HMAC)
    if type -p openssl &>/dev/null; then
        printf '[OK] openssl (for HMAC)\n'
    else
        printf '[MISSING] openssl (HMAC unavailable)\n'
    fi

    # Randomness
    if [[ -r /dev/urandom ]]; then
        printf '[OK] /dev/urandom\n'
    else
        printf '[MISSING] /dev/urandom\n'
        status=1
    fi

    return $status
}

# =============================================================================
# CONSTANT-TIME COMPARISON
# =============================================================================

# Compare two strings in constant time (mitigate timing attacks)
# Usage: constant_time_compare "string1" "string2"
# Note: Bash has inherent timing variations; this is best-effort
constant_time_compare() {
    local a="$1"
    local b="$2"
    local result=0

    # Length check
    if [[ ${#a} -ne ${#b} ]]; then
        return 1
    fi

    local i
    for ((i=0; i<${#a}; i++)); do
        local ca="${a:i:1}"
        local cb="${b:i:1}"
        local va=$(printf '%d' "'$ca")
        local vb=$(printf '%d' "'$cb")
        ((result |= va ^ vb))
    done

    [[ $result -eq 0 ]]
}

"""
MAINFRAME Utility Functions - Python wrappers for common utilities.

Wraps functions from pure-util.sh, common.sh, datetime.sh, and crypto.sh.
"""

from .core import MainframeFunctionError
from .core import _legacy_call_function as call_function

# =============================================================================
# UUID / RANDOM
# =============================================================================

def uuid() -> str:
    """
    Generate a UUID v4.

    Returns:
        UUID string in format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx

    Example:
        id = uuid()  # "550e8400-e29b-41d4-a716-446655440000"
    """
    output, code = call_function("uuid")
    if code != 0:
        raise MainframeFunctionError("uuid", "Failed to generate UUID", code)
    return output


def uuid4() -> str:
    """
    Alias for uuid(). Generate a UUID v4.

    Returns:
        UUID string.
    """
    return uuid()


def random_string(length: int = 16) -> str:
    """
    Generate a random alphanumeric string.

    Args:
        length: Length of string to generate (default: 16).

    Returns:
        Random string of specified length.

    Example:
        s = random_string(8)  # "aB3xY9Kp"
    """
    output, code = call_function("random_string", str(length))
    if code != 0:
        raise MainframeFunctionError("random_string", "Failed to generate string", code)
    return output


def random_hex(length: int = 8) -> str:
    """
    Generate a random hexadecimal string.

    Args:
        length: Length of string to generate (default: 8).

    Returns:
        Random hex string.

    Example:
        h = random_hex(8)  # "a3f7c9b2"
    """
    output, code = call_function("random_hex", str(length))
    if code != 0:
        raise MainframeFunctionError("random_hex", "Failed to generate hex", code)
    return output


def random_range(min_val: int = 0, max_val: int = 100) -> int:
    """
    Generate a random integer in range [min, max].

    Args:
        min_val: Minimum value (inclusive, default: 0).
        max_val: Maximum value (inclusive, default: 100).

    Returns:
        Random integer.

    Example:
        n = random_range(1, 10)  # Random 1-10
    """
    output, code = call_function("random_range", str(min_val), str(max_val))
    if code != 0:
        raise MainframeFunctionError("random_range", "Failed to generate number", code)
    return int(output)


# =============================================================================
# TIMESTAMPS
# =============================================================================

def timestamp() -> str:
    """
    Get current timestamp in format YYYY-MM-DD HH:MM:SS.

    Returns:
        Timestamp string.

    Example:
        ts = timestamp()  # "2024-01-15 14:30:00"
    """
    output, code = call_function("timestamp")
    if code != 0:
        raise MainframeFunctionError("timestamp", "Failed to get timestamp", code)
    return output


def timestamp_iso() -> str:
    """
    Get current timestamp in ISO 8601 format.

    Returns:
        ISO timestamp string with timezone.

    Example:
        ts = timestamp_iso()  # "2024-01-15T14:30:00-0500"
    """
    output, code = call_function("timestamp_iso")
    if code != 0:
        raise MainframeFunctionError("timestamp_iso", "Failed to get timestamp", code)
    return output


def now_iso() -> str:
    """
    Get current time as ISO 8601 string.

    Alias for timestamp_iso().

    Returns:
        ISO timestamp string.
    """
    output, code = call_function("now_iso")
    if code != 0:
        raise MainframeFunctionError("now_iso", "Failed to get timestamp", code)
    return output


def epoch() -> int:
    """
    Get current Unix timestamp (seconds since epoch).

    Returns:
        Integer seconds since 1970-01-01 00:00:00 UTC.

    Example:
        ts = epoch()  # 1705337400
    """
    output, code = call_function("epoch")
    if code != 0:
        raise MainframeFunctionError("epoch", "Failed to get epoch", code)
    return int(output)


def epoch_ms() -> int:
    """
    Get current time in milliseconds since epoch.

    Note: Bash approximation - sub-second precision not available.

    Returns:
        Integer milliseconds since epoch.

    Example:
        ts = epoch_ms()  # 1705337400000
    """
    output, code = call_function("epoch_ms")
    if code != 0:
        raise MainframeFunctionError("epoch_ms", "Failed to get epoch_ms", code)
    return int(output)


# =============================================================================
# LOGGING
# =============================================================================

def log_info(message: str) -> str:
    """
    Log an info-level message.

    Args:
        message: Message to log.

    Returns:
        Captured log output.

    Example:
        log_info("Processing started")
    """
    output, _ = call_function("log::info", message, capture_stderr=True)
    return output


def log_warn(message: str) -> str:
    """
    Log a warning-level message.

    Args:
        message: Message to log.

    Returns:
        Captured log output.

    Example:
        log_warn("Disk space low")
    """
    output, _ = call_function("log::warn", message, capture_stderr=True)
    return output


def log_error(message: str) -> str:
    """
    Log an error-level message.

    Args:
        message: Message to log.

    Returns:
        Captured log output.

    Example:
        log_error("Connection failed")
    """
    output, _ = call_function("log::error", message, capture_stderr=True)
    return output


def log_debug(message: str) -> str:
    """
    Log a debug-level message.

    Note: Only visible if BASHER_LOG_LEVEL is set to 0 (DEBUG).

    Args:
        message: Message to log.

    Returns:
        Captured log output.

    Example:
        log_debug("Variable x = 42")
    """
    output, _ = call_function(
        "log_debug",
        message,
        capture_stderr=True,
        env={"BASHER_LOG_LEVEL": "0"}
    )
    return output


# =============================================================================
# CRYPTO / HASHING
# =============================================================================

def sha256(data: str) -> str:
    """
    Calculate SHA-256 hash of a string.

    Args:
        data: String to hash.

    Returns:
        64-character hex hash string.

    Example:
        h = sha256("hello")  # "2cf24dba5fb0a30e..."
    """
    output, code = call_function("sha256", data)
    if code != 0:
        raise MainframeFunctionError("sha256", "Failed to calculate hash", code)
    return output


def sha1(data: str) -> str:
    """
    Calculate SHA-1 hash of a string.

    Args:
        data: String to hash.

    Returns:
        40-character hex hash string.

    Example:
        h = sha1("hello")  # "aaf4c61ddcc5e8a2..."
    """
    output, code = call_function("sha1", data)
    if code != 0:
        raise MainframeFunctionError("sha1", "Failed to calculate hash", code)
    return output


def md5(data: str) -> str:
    """
    Calculate MD5 hash of a string.

    Note: MD5 is cryptographically broken. Use for checksums only.

    Args:
        data: String to hash.

    Returns:
        32-character hex hash string.

    Example:
        h = md5("hello")  # "5d41402abc4b2a76..."
    """
    output, code = call_function("md5", data)
    if code != 0:
        raise MainframeFunctionError("md5", "Failed to calculate hash", code)
    return output


def base64_encode(data: str) -> str:
    """
    Encode string to base64.

    Args:
        data: String to encode.

    Returns:
        Base64 encoded string.

    Example:
        enc = base64_encode("hello")  # "aGVsbG8="
    """
    output, code = call_function("base64_encode", data)
    if code != 0:
        raise MainframeFunctionError("base64_encode", "Failed to encode", code)
    return output.strip()


def base64_decode(data: str) -> str:
    """
    Decode base64 string.

    Args:
        data: Base64 encoded string.

    Returns:
        Decoded string.

    Example:
        dec = base64_decode("aGVsbG8=")  # "hello"
    """
    output, code = call_function("base64_decode", data)
    if code != 0:
        raise MainframeFunctionError("base64_decode", "Failed to decode", code)
    return output

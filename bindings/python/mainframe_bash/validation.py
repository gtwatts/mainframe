"""
MAINFRAME Validation Functions - Python wrappers for input validation.

Wraps validation.sh functions: validate_*, sanitize_*, etc.
"""

from .core import MainframeFunctionError
from .core import _fixed_convenience_call as call_function


def validate_email(email: str) -> bool:
    """
    Validate email address format (RFC 5322 simplified).

    Args:
        email: Email address to validate.

    Returns:
        True if valid, False otherwise.

    Example:
        validate_email("test@example.com")  # True
        validate_email("invalid")           # False
    """
    _, code = call_function("validate_email", email)
    return code == 0


def validate_url(url: str, schemes: str = "http,https") -> bool:
    """
    Validate URL format.

    Args:
        url: URL to validate.
        schemes: Comma-separated list of allowed schemes.

    Returns:
        True if valid, False otherwise.

    Example:
        validate_url("https://example.com")  # True
        validate_url("ftp://example.com")    # False (default schemes)
        validate_url("ftp://x.com", "ftp")   # True
    """
    _, code = call_function("validate_url", url, schemes)
    return code == 0


def validate_uuid(value: str) -> bool:
    """
    Validate UUID format (v1-v5).

    Args:
        value: String to validate.

    Returns:
        True if valid UUID format, False otherwise.

    Example:
        validate_uuid("550e8400-e29b-41d4-a716-446655440000")  # True
        validate_uuid("not-a-uuid")                            # False
    """
    _, code = call_function("validate_uuid", value)
    return code == 0


def validate_int(
    value: str | int,
    min_val: int | None = None,
    max_val: int | None = None,
) -> bool:
    """
    Validate integer with optional range.

    Args:
        value: Value to validate.
        min_val: Minimum allowed value (optional).
        max_val: Maximum allowed value (optional).

    Returns:
        True if valid integer in range, False otherwise.

    Example:
        validate_int("42")           # True
        validate_int("42", 0, 100)   # True
        validate_int("42", 50, 100)  # False
    """
    args = [str(value)]
    if min_val is not None:
        args.append(str(min_val))
    if max_val is not None:
        if min_val is None:
            args.append("")  # placeholder for min
        args.append(str(max_val))

    _, code = call_function("validate_int", *args)
    return code == 0


def validate_float(value: str | float) -> bool:
    """
    Validate floating point number.

    Args:
        value: Value to validate.

    Returns:
        True if valid float, False otherwise.

    Example:
        validate_float("3.14")    # True
        validate_float("1e-10")   # True
        validate_float("abc")     # False
    """
    _, code = call_function("validate_float", str(value))
    return code == 0


def validate_bool(value: str | bool) -> bool:
    """
    Validate boolean value.

    Accepts: true/false/yes/no/1/0/on/off (case insensitive).

    Args:
        value: Value to validate.

    Returns:
        True if valid boolean representation, False otherwise.

    Example:
        validate_bool("true")   # True
        validate_bool("yes")    # True
        validate_bool("maybe")  # False
    """
    if isinstance(value, bool):
        return True
    _, code = call_function("validate_bool", str(value))
    return code == 0


def validate_date(date: str) -> bool:
    """
    Validate date format YYYY-MM-DD.

    Also validates the date is actually valid (correct days in month, leap years).

    Args:
        date: Date string to validate.

    Returns:
        True if valid date, False otherwise.

    Example:
        validate_date("2024-01-15")  # True
        validate_date("2024-02-30")  # False (invalid day)
    """
    _, code = call_function("validate_date", date)
    return code == 0


def validate_time(time: str) -> bool:
    """
    Validate time format HH:MM:SS.

    Args:
        time: Time string to validate.

    Returns:
        True if valid time, False otherwise.

    Example:
        validate_time("14:30:00")  # True
        validate_time("25:00:00")  # False
    """
    _, code = call_function("validate_time", time)
    return code == 0


def validate_semver(version: str) -> bool:
    """
    Validate semantic version format.

    Accepts versions with optional 'v' prefix and pre-release/build metadata.

    Args:
        version: Version string to validate.

    Returns:
        True if valid semver, False otherwise.

    Example:
        validate_semver("1.2.3")            # True
        validate_semver("v1.2.3-beta+build") # True
        validate_semver("1.2")               # False
    """
    _, code = call_function("validate_semver", version)
    return code == 0


def validate_ipv4(ip: str) -> bool:
    """
    Validate IPv4 address format.

    Args:
        ip: IP address to validate.

    Returns:
        True if valid IPv4 address, False otherwise.

    Example:
        validate_ipv4("192.168.1.1")  # True
        validate_ipv4("256.1.1.1")    # False
    """
    _, code = call_function("validate_ipv4", ip)
    return code == 0


def validate_ipv6(ip: str) -> bool:
    """
    Validate IPv6 address format.

    Args:
        ip: IP address to validate.

    Returns:
        True if valid IPv6 address, False otherwise.

    Example:
        validate_ipv6("2001:db8::1")  # True
        validate_ipv6("invalid")      # False
    """
    _, code = call_function("validate_ipv6", ip)
    return code == 0


def validate_domain(domain: str) -> bool:
    """
    Validate domain name format.

    Args:
        domain: Domain name to validate.

    Returns:
        True if valid domain, False otherwise.

    Example:
        validate_domain("example.com")  # True
        validate_domain("-invalid.com") # False
    """
    _, code = call_function("validate_domain", domain)
    return code == 0


def validate_hex(value: str, length: int | None = None) -> bool:
    """
    Validate hexadecimal string.

    Args:
        value: String to validate.
        length: Expected length (optional).

    Returns:
        True if valid hex string, False otherwise.

    Example:
        validate_hex("deadbeef")       # True
        validate_hex("abcd", 4)        # True
        validate_hex("abc", 4)         # False (wrong length)
    """
    args = [value]
    if length is not None:
        args.append(str(length))

    _, code = call_function("validate_hex", *args)
    return code == 0


def validate_path(path: str, path_type: str = "any") -> bool:
    """
    Validate path exists with optional type check.

    Args:
        path: Path to validate.
        path_type: "file", "dir", or "any" (default).

    Returns:
        True if path exists and matches type, False otherwise.

    Example:
        validate_path("/etc/passwd", "file")  # True
        validate_path("/etc", "dir")          # True
    """
    _, code = call_function("validate_path", path, path_type)
    return code == 0


def validate_path_safe(path: str, base_dir: str | None = None) -> bool:
    """
    Validate path is safe (no traversal attacks).

    Prevents: ../, symlink escapes, null bytes.

    Args:
        path: Path to validate.
        base_dir: Base directory path must stay within (optional).

    Returns:
        True if path is safe, False otherwise.

    Example:
        validate_path_safe("/app/data/file.txt", "/app/data")  # True
        validate_path_safe("../etc/passwd", "/app/data")       # False
    """
    args = [path]
    if base_dir is not None:
        args.append(base_dir)

    _, code = call_function("validate_path_safe", *args)
    return code == 0


def validate_filename(name: str) -> bool:
    """
    Validate filename (no path components).

    Rejects path separators, special names (. / ..), and leading dashes.

    Args:
        name: Filename to validate.

    Returns:
        True if valid filename, False otherwise.

    Example:
        validate_filename("report.pdf")  # True
        validate_filename("../file")     # False
        validate_filename("-flag")       # False
    """
    _, code = call_function("validate_filename", name)
    return code == 0


def validate_length(
    value: str,
    min_len: int | None = None,
    max_len: int | None = None,
) -> bool:
    """
    Validate string length.

    Args:
        value: String to validate.
        min_len: Minimum length (optional).
        max_len: Maximum length (optional).

    Returns:
        True if length is within bounds, False otherwise.

    Example:
        validate_length("hello", 1, 10)   # True
        validate_length("hi", 5, 10)      # False
    """
    args = [value]
    if min_len is not None:
        args.append(str(min_len))
    if max_len is not None:
        if min_len is None:
            args.append("")  # placeholder
        args.append(str(max_len))

    _, code = call_function("validate_length", *args)
    return code == 0


def sanitize_html(value: str) -> str:
    """
    Sanitize string for safe HTML output.

    Escapes: & < > " '

    Args:
        value: String to sanitize.

    Returns:
        HTML-safe string.

    Example:
        sanitize_html('<script>alert("xss")</script>')
        # Returns: '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;'
    """
    output, code = call_function("sanitize_html", value)
    if code != 0:
        raise MainframeFunctionError("sanitize_html", "Sanitization failed", code)
    return output


def sanitize_sql(value: str) -> str:
    """
    Sanitize string for SQL (basic escaping).

    WARNING: Prefer parameterized queries in production.

    Args:
        value: String to sanitize.

    Returns:
        SQL-safe string.

    Example:
        sanitize_sql("O'Reilly")  # "O''Reilly"
    """
    output, code = call_function("sanitize_sql", value)
    if code != 0:
        raise MainframeFunctionError("sanitize_sql", "Sanitization failed", code)
    return output


def sanitize_filename(name: str, replacement: str = "_") -> str:
    """
    Sanitize filename by removing dangerous characters.

    Args:
        name: Filename to sanitize.
        replacement: Character to replace dangerous chars with.

    Returns:
        Safe filename.

    Example:
        sanitize_filename("file/name:test.txt")  # "file_name_test.txt"
    """
    output, code = call_function("sanitize_filename", name, replacement)
    if code != 0:
        raise MainframeFunctionError("sanitize_filename", "Sanitization failed", code)
    return output


def sanitize_shell_arg(value: str) -> str:
    """
    Sanitize value for safe shell argument.

    Args:
        value: Value to sanitize.

    Returns:
        Shell-safe string.

    Example:
        sanitize_shell_arg("hello world; rm -rf /")
        # Returns properly escaped string
    """
    output, code = call_function("sanitize_shell_arg", value)
    if code != 0:
        raise MainframeFunctionError("sanitize_shell_arg", "Sanitization failed", code)
    return output

"""
Tests for mainframe_bash.validation module.
"""

import pytest

from mainframe_bash.validation import (
    validate_email,
    validate_url,
    validate_uuid,
    validate_int,
    validate_float,
    validate_bool,
    validate_date,
    validate_time,
    validate_semver,
    validate_ipv4,
    validate_ipv6,
    validate_domain,
    validate_hex,
    validate_path,
    validate_filename,
    validate_length,
    sanitize_html,
    sanitize_sql,
    sanitize_filename,
)


class TestValidateEmail:
    """Tests for email validation."""

    def test_valid_email(self):
        """Should accept valid emails."""
        assert validate_email("test@example.com") is True
        assert validate_email("user.name@domain.co.uk") is True
        assert validate_email("user+tag@example.org") is True

    def test_invalid_email(self):
        """Should reject invalid emails."""
        assert validate_email("invalid") is False
        assert validate_email("@example.com") is False
        assert validate_email("test@") is False
        assert validate_email("") is False


class TestValidateUrl:
    """Tests for URL validation."""

    def test_valid_urls(self):
        """Should accept valid URLs."""
        assert validate_url("https://example.com") is True
        assert validate_url("http://example.com/path") is True
        assert validate_url("https://example.com:8080/path?query=1") is True

    def test_invalid_urls(self):
        """Should reject invalid URLs."""
        assert validate_url("not-a-url") is False
        assert validate_url("ftp://example.com") is False  # default schemes

    def test_custom_schemes(self):
        """Should accept custom schemes."""
        assert validate_url("ftp://example.com", "ftp,sftp") is True


class TestValidateUuid:
    """Tests for UUID validation."""

    def test_valid_uuid(self):
        """Should accept valid UUIDs."""
        assert validate_uuid("550e8400-e29b-41d4-a716-446655440000") is True
        assert validate_uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") is True

    def test_invalid_uuid(self):
        """Should reject invalid UUIDs."""
        assert validate_uuid("not-a-uuid") is False
        assert validate_uuid("550e8400-e29b-41d4-a716") is False  # too short
        assert validate_uuid("") is False


class TestValidateInt:
    """Tests for integer validation."""

    def test_valid_int(self):
        """Should accept valid integers."""
        assert validate_int("42") is True
        assert validate_int("-42") is True
        assert validate_int("0") is True
        assert validate_int(42) is True

    def test_invalid_int(self):
        """Should reject non-integers."""
        assert validate_int("3.14") is False
        assert validate_int("abc") is False
        assert validate_int("") is False

    def test_range_validation(self):
        """Should validate ranges."""
        assert validate_int("50", min_val=0, max_val=100) is True
        assert validate_int("150", min_val=0, max_val=100) is False
        assert validate_int("-10", min_val=0) is False


class TestValidateFloat:
    """Tests for float validation."""

    def test_valid_float(self):
        """Should accept valid floats."""
        assert validate_float("3.14") is True
        assert validate_float("-3.14") is True
        assert validate_float("1e-10") is True
        assert validate_float("42") is True

    def test_invalid_float(self):
        """Should reject invalid floats."""
        assert validate_float("abc") is False
        assert validate_float("") is False


class TestValidateBool:
    """Tests for boolean validation."""

    def test_valid_bool(self):
        """Should accept valid booleans."""
        assert validate_bool("true") is True
        assert validate_bool("false") is True
        assert validate_bool("yes") is True
        assert validate_bool("no") is True
        assert validate_bool("1") is True
        assert validate_bool("0") is True
        assert validate_bool("on") is True
        assert validate_bool("off") is True
        assert validate_bool(True) is True
        assert validate_bool(False) is True

    def test_invalid_bool(self):
        """Should reject invalid booleans."""
        assert validate_bool("maybe") is False
        assert validate_bool("2") is False


class TestValidateDate:
    """Tests for date validation."""

    def test_valid_date(self):
        """Should accept valid dates."""
        assert validate_date("2024-01-15") is True
        assert validate_date("2024-02-29") is True  # leap year

    def test_invalid_date(self):
        """Should reject invalid dates."""
        assert validate_date("2024-02-30") is False  # invalid day
        assert validate_date("2023-02-29") is False  # not leap year
        assert validate_date("2024-13-01") is False  # invalid month
        assert validate_date("invalid") is False


class TestValidateTime:
    """Tests for time validation."""

    def test_valid_time(self):
        """Should accept valid times."""
        assert validate_time("14:30:00") is True
        assert validate_time("00:00:00") is True
        assert validate_time("23:59:59") is True

    def test_invalid_time(self):
        """Should reject invalid times."""
        assert validate_time("25:00:00") is False
        assert validate_time("14:60:00") is False
        assert validate_time("invalid") is False


class TestValidateSemver:
    """Tests for semver validation."""

    def test_valid_semver(self):
        """Should accept valid semver."""
        assert validate_semver("1.0.0") is True
        assert validate_semver("1.2.3") is True
        assert validate_semver("v1.2.3") is True
        assert validate_semver("1.2.3-beta") is True
        assert validate_semver("1.2.3+build") is True
        assert validate_semver("1.2.3-beta+build") is True

    def test_invalid_semver(self):
        """Should reject invalid semver."""
        assert validate_semver("1.2") is False
        assert validate_semver("1") is False
        assert validate_semver("invalid") is False


class TestValidateIp:
    """Tests for IP address validation."""

    def test_valid_ipv4(self):
        """Should accept valid IPv4."""
        assert validate_ipv4("192.168.1.1") is True
        assert validate_ipv4("0.0.0.0") is True
        assert validate_ipv4("255.255.255.255") is True

    def test_invalid_ipv4(self):
        """Should reject invalid IPv4."""
        assert validate_ipv4("256.1.1.1") is False
        assert validate_ipv4("192.168.1") is False
        assert validate_ipv4("invalid") is False

    def test_valid_ipv6(self):
        """Should accept valid IPv6."""
        assert validate_ipv6("2001:db8::1") is True
        assert validate_ipv6("::1") is True
        assert validate_ipv6("fe80::1") is True

    def test_invalid_ipv6(self):
        """Should reject invalid IPv6."""
        assert validate_ipv6("invalid") is False
        assert validate_ipv6("192.168.1.1") is False


class TestValidateDomain:
    """Tests for domain validation."""

    def test_valid_domain(self):
        """Should accept valid domains."""
        assert validate_domain("example.com") is True
        assert validate_domain("sub.example.com") is True
        assert validate_domain("example.co.uk") is True

    def test_invalid_domain(self):
        """Should reject invalid domains."""
        assert validate_domain("-invalid.com") is False
        assert validate_domain("invalid-.com") is False
        assert validate_domain("") is False


class TestValidateHex:
    """Tests for hex validation."""

    def test_valid_hex(self):
        """Should accept valid hex."""
        assert validate_hex("deadbeef") is True
        assert validate_hex("DEADBEEF") is True
        assert validate_hex("0123456789abcdef") is True

    def test_invalid_hex(self):
        """Should reject invalid hex."""
        assert validate_hex("ghijkl") is False
        assert validate_hex("") is False

    def test_length_validation(self):
        """Should validate hex length."""
        assert validate_hex("abcd", 4) is True
        assert validate_hex("abc", 4) is False


class TestValidatePath:
    """Tests for path validation."""

    def test_existing_file(self):
        """Should validate existing files."""
        assert validate_path("/etc/passwd", "file") is True

    def test_existing_dir(self):
        """Should validate existing directories."""
        assert validate_path("/etc", "dir") is True

    def test_nonexistent_path(self):
        """Should reject nonexistent paths."""
        assert validate_path("/nonexistent/path") is False


class TestValidateFilename:
    """Tests for filename validation."""

    def test_valid_filename(self):
        """Should accept valid filenames."""
        assert validate_filename("report.pdf") is True
        assert validate_filename("my-file_v2.txt") is True

    def test_invalid_filename(self):
        """Should reject invalid filenames."""
        assert validate_filename("../file") is False
        assert validate_filename("path/to/file") is False
        assert validate_filename("-flag") is False
        assert validate_filename(".") is False
        assert validate_filename("..") is False


class TestValidateLength:
    """Tests for length validation."""

    def test_valid_length(self):
        """Should accept valid lengths."""
        assert validate_length("hello", 1, 10) is True
        assert validate_length("hello", 5, 5) is True

    def test_invalid_length(self):
        """Should reject invalid lengths."""
        assert validate_length("hi", 5, 10) is False
        assert validate_length("hello world", 1, 5) is False


class TestSanitizeHtml:
    """Tests for HTML sanitization."""

    def test_escapes_tags(self):
        """Should escape HTML tags."""
        result = sanitize_html("<script>alert('xss')</script>")
        assert "<" not in result
        assert ">" not in result
        assert "&lt;" in result
        assert "&gt;" in result

    def test_escapes_quotes(self):
        """Should escape quotes."""
        result = sanitize_html('hello "world"')
        assert "&quot;" in result

    def test_escapes_ampersand(self):
        """Should escape ampersand."""
        result = sanitize_html("Tom & Jerry")
        assert "&amp;" in result


class TestSanitizeSql:
    """Tests for SQL sanitization."""

    def test_escapes_quotes(self):
        """Should escape single quotes."""
        result = sanitize_sql("O'Reilly")
        assert "''" in result


class TestSanitizeFilename:
    """Tests for filename sanitization."""

    def test_removes_path_components(self):
        """Should remove path separators."""
        result = sanitize_filename("path/to/file.txt")
        assert "/" not in result

    def test_removes_special_chars(self):
        """Should remove shell metacharacters."""
        result = sanitize_filename("file;rm -rf /;.txt")
        assert ";" not in result
        assert "/" not in result

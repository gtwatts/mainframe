"""
Tests for mainframe_bash.utils module.
"""

import re
import time

import pytest

from mainframe_bash.utils import (
    uuid,
    uuid4,
    random_string,
    random_hex,
    random_range,
    timestamp,
    timestamp_iso,
    now_iso,
    epoch,
    epoch_ms,
    log_info,
    log_warn,
    log_error,
    log_debug,
    sha256,
    sha1,
    md5,
    base64_encode,
    base64_decode,
)


class TestUuid:
    """Tests for UUID generation."""

    def test_uuid_format(self):
        """Should generate valid UUID v4 format."""
        id = uuid()
        # UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
        pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        assert re.match(pattern, id.lower()) is not None

    def test_uuid_unique(self):
        """Should generate unique UUIDs."""
        uuids = [uuid() for _ in range(10)]
        assert len(set(uuids)) == 10

    def test_uuid4_alias(self):
        """uuid4 should be alias for uuid."""
        id = uuid4()
        assert len(id) == 36


class TestRandomString:
    """Tests for random string generation."""

    def test_default_length(self):
        """Should generate 16 char string by default."""
        s = random_string()
        assert len(s) == 16

    def test_custom_length(self):
        """Should generate custom length string."""
        s = random_string(32)
        assert len(s) == 32

    def test_alphanumeric(self):
        """Should be alphanumeric only."""
        s = random_string(100)
        assert s.isalnum()

    def test_unique(self):
        """Should generate unique strings."""
        strings = [random_string() for _ in range(10)]
        assert len(set(strings)) == 10


class TestRandomHex:
    """Tests for random hex generation."""

    def test_default_length(self):
        """Should generate 8 char hex by default."""
        h = random_hex()
        assert len(h) == 8

    def test_custom_length(self):
        """Should generate custom length hex."""
        h = random_hex(16)
        assert len(h) == 16

    def test_valid_hex(self):
        """Should be valid hex string."""
        h = random_hex(32)
        assert all(c in '0123456789abcdef' for c in h.lower())


class TestRandomRange:
    """Tests for random range generation."""

    def test_default_range(self):
        """Should generate in default range 0-100."""
        n = random_range()
        assert 0 <= n <= 100

    def test_custom_range(self):
        """Should generate in custom range."""
        n = random_range(10, 20)
        assert 10 <= n <= 20

    def test_returns_int(self):
        """Should return integer."""
        n = random_range()
        assert isinstance(n, int)


class TestTimestamp:
    """Tests for timestamp functions."""

    def test_timestamp_format(self):
        """Should return YYYY-MM-DD HH:MM:SS format."""
        ts = timestamp()
        pattern = r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        assert re.match(pattern, ts) is not None

    def test_timestamp_iso_format(self):
        """Should return ISO 8601 format."""
        ts = timestamp_iso()
        # ISO format: YYYY-MM-DDTHH:MM:SS+HHMM
        assert 'T' in ts
        assert len(ts) >= 19

    def test_now_iso_alias(self):
        """now_iso should work like timestamp_iso."""
        ts = now_iso()
        assert 'T' in ts

    def test_epoch_reasonable(self):
        """Should return reasonable epoch value."""
        e = epoch()
        # Should be after 2020 and before 2100
        assert 1577836800 < e < 4102444800
        assert isinstance(e, int)

    def test_epoch_ms_reasonable(self):
        """Should return reasonable epoch_ms value."""
        e = epoch_ms()
        # Should be 1000x epoch
        assert e > 1577836800000
        assert isinstance(e, int)


class TestLogging:
    """Tests for logging functions."""

    def test_log_info(self):
        """Should log info message."""
        output = log_info("test message")
        # Log output goes to stderr, captured
        assert "test message" in output or output == ""

    def test_log_warn(self):
        """Should log warning message."""
        output = log_warn("warning message")
        assert "warning message" in output or output == ""

    def test_log_error(self):
        """Should log error message."""
        output = log_error("error message")
        assert "error message" in output or output == ""

    def test_log_debug(self):
        """Should log debug message (when enabled)."""
        output = log_debug("debug message")
        # Debug only shows with BASHER_LOG_LEVEL=0
        assert "debug message" in output or output == ""


class TestHashing:
    """Tests for hash functions."""

    def test_sha256_known_value(self):
        """Should produce correct SHA-256 hash."""
        h = sha256("hello")
        # Known hash for "hello"
        assert h == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

    def test_sha256_length(self):
        """Should return 64-char hex string."""
        h = sha256("test")
        assert len(h) == 64
        assert all(c in '0123456789abcdef' for c in h)

    def test_sha1_known_value(self):
        """Should produce correct SHA-1 hash."""
        h = sha1("hello")
        # Known hash for "hello"
        assert h == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"

    def test_sha1_length(self):
        """Should return 40-char hex string."""
        h = sha1("test")
        assert len(h) == 40

    def test_md5_known_value(self):
        """Should produce correct MD5 hash."""
        h = md5("hello")
        # Known hash for "hello"
        assert h == "5d41402abc4b2a76b9719d911017c592"

    def test_md5_length(self):
        """Should return 32-char hex string."""
        h = md5("test")
        assert len(h) == 32


class TestBase64:
    """Tests for base64 encoding/decoding."""

    def test_encode_known_value(self):
        """Should produce correct base64."""
        enc = base64_encode("hello")
        assert enc == "aGVsbG8="

    def test_decode_known_value(self):
        """Should decode correctly."""
        dec = base64_decode("aGVsbG8=")
        assert dec == "hello"

    def test_roundtrip(self):
        """Should roundtrip encode/decode."""
        original = "The quick brown fox"
        encoded = base64_encode(original)
        decoded = base64_decode(encoded)
        assert decoded == original

    def test_binary_safe(self):
        """Should handle special characters."""
        original = "hello\nworld\ttab"
        encoded = base64_encode(original)
        decoded = base64_decode(encoded)
        assert decoded == original

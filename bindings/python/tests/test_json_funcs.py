"""
Tests for mainframe_bash.json_funcs module.
"""

import pytest

from mainframe_bash.json_funcs import (
    json_object,
    json_array,
    json_string,
    json_escape,
    json_value,
    json_merge,
    json_pretty,
)


class TestJsonObject:
    """Tests for json_object function."""

    def test_simple_object(self):
        """Should create simple object."""
        obj = json_object(name="John")
        assert obj == {"name": "John"}

    def test_multiple_keys(self):
        """Should handle multiple keys."""
        obj = json_object(name="John", city="NYC")
        assert obj == {"name": "John", "city": "NYC"}

    def test_integer_value(self):
        """Should handle integer values."""
        obj = json_object(age=30)
        assert obj == {"age": 30}
        assert isinstance(obj["age"], int)

    def test_float_value(self):
        """Should handle float values."""
        obj = json_object(score=3.14)
        assert obj == {"score": 3.14}
        assert isinstance(obj["score"], float)

    def test_boolean_value(self):
        """Should handle boolean values."""
        obj = json_object(active=True, deleted=False)
        assert obj == {"active": True, "deleted": False}
        assert obj["active"] is True
        assert obj["deleted"] is False

    def test_null_value(self):
        """Should handle None as null."""
        obj = json_object(data=None)
        assert obj == {"data": None}
        assert obj["data"] is None

    def test_mixed_types(self):
        """Should handle mixed types."""
        obj = json_object(
            name="John",
            age=30,
            score=3.14,
            active=True,
            data=None
        )
        assert obj["name"] == "John"
        assert obj["age"] == 30
        assert obj["score"] == 3.14
        assert obj["active"] is True
        assert obj["data"] is None


class TestJsonArray:
    """Tests for json_array function."""

    def test_string_array(self):
        """Should create string array."""
        arr = json_array("a", "b", "c")
        assert arr == ["a", "b", "c"]

    def test_number_array(self):
        """Should create number array."""
        arr = json_array(1, 2, 3)
        assert arr == [1, 2, 3]

    def test_mixed_array(self):
        """Should create mixed type array."""
        arr = json_array("a", 1, True)
        assert arr == ["a", 1, True]

    def test_empty_array(self):
        """Should create empty array."""
        arr = json_array()
        assert arr == []


class TestJsonString:
    """Tests for json_string function."""

    def test_simple_string(self):
        """Should create JSON string."""
        s = json_string("hello")
        assert s == '"hello"'

    def test_string_with_quotes(self):
        """Should escape quotes."""
        s = json_string('hello "world"')
        assert '\\"' in s

    def test_string_with_backslash(self):
        """Should escape backslashes."""
        s = json_string("path\\to\\file")
        assert "\\\\" in s


class TestJsonEscape:
    """Tests for json_escape function."""

    def test_simple_string(self):
        """Should not modify simple strings."""
        s = json_escape("hello")
        assert s == "hello"

    def test_newline_escape(self):
        """Should escape newlines."""
        s = json_escape("hello\nworld")
        assert s == "hello\\nworld"

    def test_tab_escape(self):
        """Should escape tabs."""
        s = json_escape("hello\tworld")
        assert s == "hello\\tworld"

    def test_quote_escape(self):
        """Should escape quotes."""
        s = json_escape('hello "world"')
        assert s == 'hello \\"world\\"'


class TestJsonValue:
    """Tests for json_value function."""

    def test_auto_string(self):
        """Should auto-detect strings."""
        v = json_value("hello", "auto")
        assert v == '"hello"'

    def test_auto_number(self):
        """Should auto-detect numbers."""
        v = json_value("42", "auto")
        assert v == "42"

    def test_explicit_number(self):
        """Should force number type."""
        v = json_value("42", "number")
        assert v == "42"

    def test_explicit_string(self):
        """Should force string type."""
        v = json_value("42", "string")
        assert v == '"42"'

    def test_explicit_bool(self):
        """Should handle bool type."""
        v = json_value("true", "bool")
        assert v == "true"

    def test_explicit_null(self):
        """Should handle null type."""
        v = json_value("anything", "null")
        assert v == "null"


class TestJsonMerge:
    """Tests for json_merge function."""

    def test_merge_two_objects(self):
        """Should merge two objects."""
        merged = json_merge({"a": 1}, {"b": 2})
        assert merged == {"a": 1, "b": 2}

    def test_merge_three_objects(self):
        """Should merge multiple objects."""
        merged = json_merge({"a": 1}, {"b": 2}, {"c": 3})
        assert merged == {"a": 1, "b": 2, "c": 3}

    def test_merge_empty(self):
        """Should handle empty objects."""
        merged = json_merge({}, {"a": 1})
        assert merged == {"a": 1}


class TestJsonPretty:
    """Tests for json_pretty function."""

    def test_pretty_object(self):
        """Should format object."""
        pretty = json_pretty({"a": 1, "b": 2})
        assert "\n" in pretty
        assert "a" in pretty
        assert "b" in pretty

    def test_pretty_array(self):
        """Should format array."""
        pretty = json_pretty([1, 2, 3])
        assert "\n" in pretty

    def test_custom_indent(self):
        """Should use custom indent."""
        pretty = json_pretty({"a": 1}, "    ")
        assert "    " in pretty

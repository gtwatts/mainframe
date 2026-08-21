"""
MAINFRAME JSON Functions - Python wrappers for JSON generation.

Wraps json.sh functions: json_object, json_array, json_string, etc.
"""

import json
from typing import Any, cast

from .core import MainframeFunctionError
from .core import _fixed_convenience_call as call_function
from .core import _fixed_convenience_json as call_function_json


def json_object(**kwargs: str | int | float | bool | None) -> dict[str, Any]:
    """
    Create a JSON object from keyword arguments.

    Wraps MAINFRAME json_object function. Automatically detects types
    and creates properly typed JSON values.

    Args:
        **kwargs: Key-value pairs for the object.

    Returns:
        Python dict representing the JSON object.

    Example:
        obj = json_object(name="John", age=30, active=True)
        # Returns: {"name": "John", "age": 30, "active": true}
    """
    # Build MAINFRAME-style key=value or key:type=value arguments
    args = []
    for key, value in kwargs.items():
        if value is None:
            args.append(f"{key}:null=null")
        elif isinstance(value, bool):
            args.append(f"{key}:bool={'true' if value else 'false'}")
        elif isinstance(value, int):
            args.append(f"{key}:number={value}")
        elif isinstance(value, float):
            args.append(f"{key}:number={value}")
        else:
            args.append(f"{key}={value}")

    return cast(dict[str, Any], call_function_json("json_object", *args))


def json_array(*items: str | int | float | bool | None) -> list[Any]:
    """
    Create a JSON array from arguments.

    Wraps MAINFRAME json_array function. Automatically detects types.

    Args:
        *items: Values to include in the array.

    Returns:
        Python list representing the JSON array.

    Example:
        arr = json_array("a", "b", 1, 2, True)
        # Returns: ["a", "b", 1, 2, true]
    """
    # Convert Python values to strings for MAINFRAME
    str_items = []
    for item in items:
        if item is None:
            str_items.append("null")
        elif isinstance(item, bool):
            str_items.append("true" if item else "false")
        else:
            str_items.append(str(item))

    return cast(list[Any], call_function_json("json_array", *str_items))


def json_string(value: str) -> str:
    """
    Create a JSON string with proper escaping.

    Wraps MAINFRAME json_string function.

    Args:
        value: String to convert to JSON string.

    Returns:
        JSON string (with quotes).

    Example:
        s = json_string('hello "world"')
        # Returns: '"hello \"world\""'
    """
    output, code = call_function("json_string", value)
    if code != 0:
        raise MainframeFunctionError("json_string", "Failed to create JSON string", code)
    return output


def json_escape(value: str) -> str:
    """
    Escape a string for inclusion in JSON.

    Wraps MAINFRAME json_escape function. Escapes special characters
    like quotes, backslashes, newlines, etc.

    Args:
        value: String to escape.

    Returns:
        Escaped string (without quotes).

    Example:
        s = json_escape('hello\nworld')
        # Returns: 'hello\\nworld'
    """
    output, code = call_function("json_escape", value)
    if code != 0:
        raise MainframeFunctionError("json_escape", "Failed to escape string", code)
    return output


def json_value(value: Any, value_type: str = "auto") -> str:
    """
    Create a JSON value with explicit type.

    Wraps MAINFRAME json_value function.

    Args:
        value: Value to convert.
        value_type: Type hint - "auto", "string", "number", "bool", "null", "raw"

    Returns:
        JSON value as string.

    Example:
        v = json_value("42", "number")
        # Returns: '42'

        v = json_value("42", "string")
        # Returns: '"42"'
    """
    output, code = call_function("json_value", str(value), value_type)
    if code != 0:
        raise MainframeFunctionError("json_value", "Failed to create JSON value", code)
    return output


def json_merge(*objects: dict | str) -> dict[str, Any]:
    """
    Merge multiple JSON objects.

    Wraps MAINFRAME json_merge function. Performs shallow merge.

    Args:
        *objects: JSON objects to merge (as dicts or JSON strings).

    Returns:
        Merged JSON object.

    Example:
        merged = json_merge({"a": 1}, {"b": 2})
        # Returns: {"a": 1, "b": 2}
    """
    # Convert dicts to JSON strings
    json_strings = []
    for obj in objects:
        if isinstance(obj, dict):
            json_strings.append(json.dumps(obj))
        else:
            json_strings.append(str(obj))

    return cast(dict[str, Any], call_function_json("json_merge", *json_strings))


def json_pretty(obj: dict | list | str, indent: str = "  ") -> str:
    """
    Pretty-print a JSON value.

    Wraps MAINFRAME json_pretty function.

    Args:
        obj: JSON object/array to format (as dict, list, or JSON string).
        indent: Indentation string (default: two spaces).

    Returns:
        Formatted JSON string.

    Example:
        pretty = json_pretty({"a": 1, "b": 2})
        # Returns formatted multi-line JSON
    """
    if isinstance(obj, dict | list):
        json_str = json.dumps(obj)
    else:
        json_str = str(obj)

    output, code = call_function("json_pretty", json_str, indent)
    if code != 0:
        raise MainframeFunctionError("json_pretty", "Failed to format JSON", code)
    return output

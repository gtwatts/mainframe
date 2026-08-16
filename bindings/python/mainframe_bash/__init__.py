"""
MAINFRAME Python Bindings

Python wrappers for MAINFRAME bash function library.
Enables calling MAINFRAME functions from Python with proper type hints
and automatic JSON response parsing.

Example:
    from mainframe_bash import json_object, validate_email, uuid

    obj = json_object(name="John", age=30, active=True)
    is_valid = validate_email("test@example.com")
    id = uuid()
"""

__version__ = "0.1.0"
__author__ = "MAINFRAME Project"

from .core import (
    BrokerInvocationResult,
    MainframeBrokerError,
    MainframeError,
    MainframeFunctionError,
    MainframeNotFoundError,
    call_function,
    call_function_json,
    exec_bash,
    get_mainframe_root,
    invoke_canonical,
)
from .json_funcs import (
    json_array,
    json_escape,
    json_merge,
    json_object,
    json_pretty,
    json_string,
    json_value,
)
from .utils import (
    base64_decode,
    base64_encode,
    epoch,
    epoch_ms,
    log_debug,
    log_error,
    log_info,
    log_warn,
    md5,
    now_iso,
    random_hex,
    random_range,
    random_string,
    sha1,
    sha256,
    timestamp,
    timestamp_iso,
    uuid,
    uuid4,
)
from .validation import (
    sanitize_filename,
    sanitize_html,
    sanitize_shell_arg,
    sanitize_sql,
    validate_bool,
    validate_date,
    validate_domain,
    validate_email,
    validate_filename,
    validate_float,
    validate_hex,
    validate_int,
    validate_ipv4,
    validate_ipv6,
    validate_length,
    validate_path,
    validate_path_safe,
    validate_semver,
    validate_time,
    validate_url,
    validate_uuid,
)

__all__ = [
    # Core
    "MainframeError",
    "MainframeNotFoundError",
    "MainframeFunctionError",
    "MainframeBrokerError",
    "BrokerInvocationResult",
    "get_mainframe_root",
    "exec_bash",
    "invoke_canonical",
    "call_function",
    "call_function_json",
    # JSON
    "json_object",
    "json_array",
    "json_string",
    "json_escape",
    "json_value",
    "json_merge",
    "json_pretty",
    # Validation
    "validate_email",
    "validate_url",
    "validate_uuid",
    "validate_int",
    "validate_float",
    "validate_bool",
    "validate_date",
    "validate_time",
    "validate_semver",
    "validate_ipv4",
    "validate_ipv6",
    "validate_domain",
    "validate_hex",
    "validate_path",
    "validate_path_safe",
    "validate_filename",
    "validate_length",
    "sanitize_html",
    "sanitize_sql",
    "sanitize_filename",
    "sanitize_shell_arg",
    # Utils
    "uuid",
    "uuid4",
    "timestamp",
    "timestamp_iso",
    "now_iso",
    "epoch",
    "epoch_ms",
    "random_string",
    "random_hex",
    "random_range",
    "log_info",
    "log_warn",
    "log_error",
    "log_debug",
    "sha256",
    "sha1",
    "md5",
    "base64_encode",
    "base64_decode",
]

"""
Pytest configuration for MAINFRAME Python bindings tests.
"""

import sys
from pathlib import Path

import pytest

# Add package to path for testing
package_dir = Path(__file__).parent.parent
sys.path.insert(0, str(package_dir))


@pytest.fixture(autouse=True)
def reset_mainframe_cache():
    """Reset MAINFRAME root cache between tests."""
    import os

    import mainframe_bash.core as core

    original = core._mainframe_root
    original_bash = core._RESOLVED_BASH
    original_env_root = os.environ.get("MAINFRAME_ROOT")
    repository_root = package_dir.parent.parent
    os.environ["MAINFRAME_ROOT"] = str(repository_root)
    core._mainframe_root = None
    yield
    core._mainframe_root = original
    core._RESOLVED_BASH = original_bash
    if original_env_root is None:
        os.environ.pop("MAINFRAME_ROOT", None)
    else:
        os.environ["MAINFRAME_ROOT"] = original_env_root


@pytest.fixture
def mainframe_root():
    """Get MAINFRAME root path."""
    from mainframe_bash.core import get_mainframe_root
    return get_mainframe_root()

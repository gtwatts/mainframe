"""
Pytest configuration for MAINFRAME Python bindings tests.
"""

import os
import sys
from pathlib import Path

import pytest

# Add package to path for testing
package_dir = Path(__file__).parent.parent
sys.path.insert(0, str(package_dir))


@pytest.fixture(autouse=True)
def reset_mainframe_cache():
    """Reset MAINFRAME root cache between tests."""
    import mainframe_bash.core as core
    original = core._mainframe_root
    yield
    core._mainframe_root = original


@pytest.fixture
def mainframe_root():
    """Get MAINFRAME root path."""
    from mainframe_bash.core import get_mainframe_root
    return get_mainframe_root()

"""Fail-closed wrapper around uv_build for distributable MCP artifacts."""

from __future__ import annotations

from pathlib import Path
import re

import uv_build


BINDING_PATH = Path(__file__).parent / 'src' / 'mainframe_mcp' / '_runtime_release.py'
BINDING_RE = re.compile(
    r"^EXPECTED_RUNTIME_INVENTORY_SHA256 = '([0-9a-f]{64})'$",
    re.MULTILINE,
)


def _require_release_binding() -> None:
    """Prevent ordinary builds from creating publishable unbound artifacts."""
    try:
        text = BINDING_PATH.read_text(encoding='utf-8')
    except OSError as error:
        raise RuntimeError('mainframe-mcp runtime binding is unavailable') from error
    if not BINDING_RE.search(text):
        raise RuntimeError(
            'mainframe-mcp distributions require the runtime-bound candidate '
            'builder; direct wheel/sdist builds are forbidden'
        )


def build_sdist(sdist_directory, config_settings=None):
    _require_release_binding()
    return uv_build.build_sdist(sdist_directory, config_settings)


def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    _require_release_binding()
    return uv_build.build_wheel(
        wheel_directory, config_settings, metadata_directory
    )


def prepare_metadata_for_build_wheel(metadata_directory, config_settings=None):
    _require_release_binding()
    return uv_build.prepare_metadata_for_build_wheel(
        metadata_directory, config_settings
    )


def get_requires_for_build_sdist(config_settings=None):
    return uv_build.get_requires_for_build_sdist(config_settings)


def get_requires_for_build_wheel(config_settings=None):
    return uv_build.get_requires_for_build_wheel(config_settings)


# Editable source installs are maintainer-only and cannot use strict release
# mode until the isolated candidate builder has generated a runtime binding.
def build_editable(wheel_directory, config_settings=None, metadata_directory=None):
    return uv_build.build_editable(
        wheel_directory, config_settings, metadata_directory
    )


def get_requires_for_build_editable(config_settings=None):
    return uv_build.get_requires_for_build_editable(config_settings)


def prepare_metadata_for_build_editable(metadata_directory, config_settings=None):
    return uv_build.prepare_metadata_for_build_editable(
        metadata_directory, config_settings
    )

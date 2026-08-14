#!/usr/bin/env python3
"""CLI entry point for MAINFRAME offline mechanism evidence generation."""

import importlib
import sys

sys.dont_write_bytecode = True

build_main = importlib.import_module("offline_evidence").build_main


if __name__ == "__main__":
    raise SystemExit(build_main())

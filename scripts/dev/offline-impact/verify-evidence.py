#!/usr/bin/env python3
"""CLI entry point for MAINFRAME offline mechanism evidence verification."""

import importlib
import sys

sys.dont_write_bytecode = True

verify_main = importlib.import_module("offline_evidence").verify_main


if __name__ == "__main__":
    raise SystemExit(verify_main())

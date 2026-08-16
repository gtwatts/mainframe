#!/usr/bin/env python3
"""Dormant Pi/Ollama adapter placeholder.

This file is digest-bound by the offline preflight.  It intentionally exposes
no invocation or run action and contains no provider, network, Pi, Ollama, or
subprocess implementation.  A future execution-capable adapter requires a new
version, review, containment proof, and explicit live-run authorization.
"""

import sys


def main() -> int:
    sys.stderr.write("Pi/Ollama adapter v1 is dormant; invocation is unsupported.\n")
    return 64


if __name__ == "__main__":
    raise SystemExit(main())

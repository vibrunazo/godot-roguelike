#!/usr/bin/env python3
"""godot-agent-kit entry point. From the game's project root:

    python addons/godot_kit/kit.py --help
"""

import sys

# The kit is vendored into games: keep __pycache__ out of their trees.
sys.dont_write_bytecode = True
# Engine output can hold any character; never crash on a narrow console encoding.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(errors="replace")

from cli.main import run  # noqa: E402

if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))

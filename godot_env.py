"""Shared Godot executable resolution for the project's Python runners.

Every runner (run_tests.py, run_scratch.py, capture.py, tools/levels/build_level.py)
launches Godot through resolve_godot() so they all agree on which binary runs and
how it is killed on timeout.

Why the binary must be the engine itself, not a launcher shim: a watchdog timeout
kills only the process Python started. If that process is a Windows .cmd/.bat
shim, cmd.exe dies but the engine it started keeps running and keeps the output
pipes open, so a runner that captures output then blocks forever draining them.
Shims are therefore unwrapped to the executable they call. Unix wrapper scripts
must `exec` the engine for the same reason.
"""

import os
import re
import shutil
from pathlib import Path


def resolve_godot() -> str:
    """Returns the Godot engine executable to launch.

    Order: the GODOT_BIN environment variable (pin a specific engine per machine
    or CI), else `godot` on PATH. A Windows .cmd/.bat shim on PATH is unwrapped
    to the quoted .exe it launches; a shim that cannot be unwrapped is an error
    rather than a silent hang risk.
    """
    override = os.environ.get("GODOT_BIN", "").strip()
    if override:
        return override
    binary = shutil.which("godot") or "godot"
    if Path(binary).suffix.lower() in (".cmd", ".bat"):
        match = re.search(r'"([^"]+\.exe)"', Path(binary).read_text(errors="replace"))
        if not match:
            raise RuntimeError(
                f"Cannot unwrap the Godot shim {binary}. Set GODOT_BIN to the engine "
                "executable (e.g. Godot_v4.7.2-stable_win64.exe)."
            )
        return match.group(1)
    return binary

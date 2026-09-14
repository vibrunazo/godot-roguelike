#!/usr/bin/env python3
"""OS-Agnostic Scratch & Diagnostic Script Runner for Godot.

Runs standalone GDScript files headlessly with an external OS-level watchdog timeout.
Enforces the universal Godot engine requirement: scripts executed via -s must extend SceneTree
and call quit() to prevent indefinite hangs.
Extra arguments after the script path are forwarded to the running script as
Godot user args (readable via OS.get_cmdline_user_args()).

Usage:
    python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_1.tscn
    python run_scratch.py tools/levels/dump_cells.gd --timeout 15 -- --level=Levels/level_1.tscn

"""

import argparse
import os
import shutil
import subprocess
import sys

DEFAULT_TIMEOUT = 15  # seconds


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a scratch GDScript headlessly with an OS watchdog timeout.")
    parser.add_argument("script", help="Path to GDScript file (e.g. tools/levels/dump_cells.gd)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help=f"Timeout in seconds (default: {DEFAULT_TIMEOUT})")
    args, extra_args = parser.parse_known_args()
    # Allow `--` as an explicit separator: everything after it is forwarded.
    extra_args = [a for a in extra_args if a != "--"]

    script_path = args.script
    if not os.path.exists(script_path):
        print(f"ERROR: Script file not found: {script_path}", file=sys.stderr)
        return 1

    # Validate Godot engine requirement: -s scripts must extend SceneTree or MainLoop
    with open(script_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    if not ("extends SceneTree" in content or "extends MainLoop" in content):
        print(
            f"ERROR: Godot engine invariant violation in '{script_path}':\n"
            f"Scripts executed via 'godot -s' MUST inherit 'SceneTree' (or 'MainLoop') and call 'quit(code)'.\n"
            f"If your script extends Node or Node3D, Godot will hang indefinitely without processing frames.\n"
            f"Fix your script to start with 'extends SceneTree' and call 'quit(0)' in _init() or when done.",
            file=sys.stderr,
        )
        return 1

    if "quit(" not in content:
        print(
            f"WARNING: Script '{script_path}' does not contain an explicit 'quit()' call.\n"
            f"It may run until the watchdog timeout of {args.timeout}s.\n",
            file=sys.stderr,
        )

    # OS-agnostic binary resolution (works on Linux, WSL, macOS, and Windows)
    godot_bin = shutil.which("godot") or "godot"

    cmd = [
        godot_bin,
        "--headless",
        "--path", ".",
        "--quit-after", "60",
        "-s", script_path,
    ]
    if extra_args:
        cmd.append("--")
        cmd.extend(extra_args)

    try:
        res = subprocess.run(
            cmd,
            shell=False,
            capture_output=True,
            text=True,
            timeout=args.timeout,
        )
        if res.stdout:
            print(res.stdout, end="")
        if res.stderr:
            print(res.stderr, file=sys.stderr, end="")
        return res.returncode
    except subprocess.TimeoutExpired:
        print(f"ERROR: Godot process timed out after {args.timeout} seconds and was forcefully terminated.", file=sys.stderr)
        return 124


if __name__ == "__main__":
    sys.exit(main())

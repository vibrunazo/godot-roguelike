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
import sys

from godot_env import ensure_class_cache, run_godot

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

    extends_line = next((line.strip() for line in content.splitlines() if line.strip().startswith("extends ")), "")
    if extends_line not in ("extends SceneTree", "extends MainLoop"):
        print(
            f"ERROR: Godot engine invariant violation in '{script_path}':\n"
            f"Scripts executed via 'godot -s' MUST inherit 'SceneTree' (or 'MainLoop') and call 'quit(code)'.\n"
            f"If your script extends Node or Node3D, Godot will hang indefinitely without processing frames.\n"
            f"Fix your script to start with 'extends SceneTree' and call 'quit(0)' when done (work in _initialize(), not _init()).",
            file=sys.stderr,
        )
        return 1

    if "quit(" not in content:
        print(
            f"WARNING: Script '{script_path}' does not contain an explicit 'quit()' call.\n"
            f"It may run until the watchdog timeout of {args.timeout}s.\n",
            file=sys.stderr,
        )

    if not ensure_class_cache():
        return 1

    # No --quit-after: it counts main-loop iterations and would cut a script
    # that awaits frames short. quit() ends the run; the watchdog backs it up.
    engine_args = ["--headless", "--path", ".", "-s", script_path]
    if extra_args:
        engine_args.append("--")
        engine_args.extend(extra_args)

    # Output streams live, so a hung script still shows how far it got.
    res = run_godot(
        engine_args,
        args.timeout,
        on_stdout=lambda line: print(line, end="", flush=True),
        on_stderr=lambda line: print(line, end="", file=sys.stderr, flush=True),
    )
    if res.timed_out:
        print(f"ERROR: Godot process timed out after {args.timeout} seconds and was forcefully terminated.", file=sys.stderr)
        return 124
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())

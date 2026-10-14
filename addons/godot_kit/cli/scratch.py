"""`kit.py scratch`: runs a throwaway GDScript headlessly under a watchdog.

The script runs with -s, so it must `extends SceneTree` (or MainLoop), do its
work in _initialize() (in _init() autoloads do not exist yet) and call
quit(code) on every path. Its own declarations must not use game class types
(`var s: Spaceship`): they compile with the script, before autoloads are
registered, so the game scripts they pull in fail with "Identifier not found"
for every autoload. Use Node and get()/call() instead.

Frames run back to back at a fixed timestep (--fixed-fps, like `test`): a
script that simulates thousands of physics ticks finishes in seconds and the
simulation is identical to a real-time run. --fps 0 restores wall-clock
pacing, for the rare script that measures real time. Never speed a run up
with Engine.time_scale instead: it lengthens every physics step, which changes
the simulation itself.

Arguments after `--` are forwarded to the script (OS.get_cmdline_user_args()).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .godot_env import ensure_class_cache, run_godot
from .project import Project


def add_parser(subparsers: argparse._SubParsersAction, parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("scratch", parents=parents, help="Run a throwaway -s script under a watchdog",
                                   description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("script", help="Path to the GDScript file (e.g. .scratch/probe.gd)")
    parser.add_argument("--timeout", type=int, help="Seconds before the run is killed (default: scratch.timeout)")
    parser.add_argument("--fps", type=int, help="Fixed render frame rate (default: scratch.fps); 0 paces frames to wall-clock time")


def run(args: argparse.Namespace, project: Project) -> int:
    timeout: int = args.timeout or project.config["scratch"]["timeout"]
    fps: int = project.config["scratch"]["fps"] if args.fps is None else args.fps
    script = Path(args.script)
    script_path = script if script.is_absolute() else project.root / script
    if not script_path.is_file():
        print(f"ERROR: Script file not found: {args.script}", file=sys.stderr)
        return 1
    content = script_path.read_text(encoding="utf-8", errors="replace")
    extends_line = next((line.strip() for line in content.splitlines() if line.strip().startswith("extends ")), "")
    if extends_line not in ("extends SceneTree", "extends MainLoop"):
        print(
            f"ERROR: '{args.script}' cannot run with -s.\n"
            "Scripts executed via 'godot -s' MUST inherit 'SceneTree' (or 'MainLoop') and call 'quit(code)'.\n"
            "A script that extends Node or Node3D never processes a frame and hangs until the watchdog kills it.\n"
            "Start it with 'extends SceneTree', do the work in _initialize() (not _init()) and call quit(0) when done.",
            file=sys.stderr,
        )
        return 1
    if "quit(" not in content:
        print(f"WARNING: '{args.script}' has no explicit quit() call; it may run until the {timeout}s watchdog.", file=sys.stderr)
    if fps < 0:
        print(f"ERROR: --fps must be 0 (real time) or positive, got {fps}.", file=sys.stderr)
        return 1
    if not ensure_class_cache(project):
        return 1
    # No --quit-after: it counts main-loop iterations and would cut a script
    # that awaits frames short. quit() ends the run; the watchdog backs it up.
    engine_args = ["--headless"] + (["--fixed-fps", str(fps)] if fps > 0 else [])
    engine_args += ["--path", ".", "-s", _engine_path(project, script_path)]
    if args.forwarded:
        engine_args += ["--", *args.forwarded]
    # Output streams live, so a hung script still shows how far it got.
    result = run_godot(
        project, engine_args, timeout,
        on_stdout=lambda line: print(line, end="", flush=True),
        on_stderr=lambda line: print(line, end="", file=sys.stderr, flush=True),
    )
    if result.timed_out:
        print(f"ERROR: Godot timed out after {timeout} seconds and was killed.", file=sys.stderr)
        return 124
    return int(result.returncode or 0)


def _engine_path(project: Project, script_path: Path) -> str:
    """The script as Godot should load it: project-relative when inside the project."""
    try:
        return script_path.resolve().relative_to(project.root.resolve()).as_posix()
    except ValueError:
        return script_path.resolve().as_posix()

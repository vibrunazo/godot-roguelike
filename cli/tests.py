"""`kit.py test`: runs the project's suites headlessly, each in its own Godot
process under a watchdog.

A suite passes only when Godot exits 0 AND its output holds no script error
(Godot skips the rest of a function after a script error instead of failing,
so an exit code alone can report a broken suite as passing).

Frames run back to back at a fixed timestep (--fixed-fps): game time advances
exactly 1/fps per frame without waiting on the wall clock, so a whole suite
takes about a second. --fps runs the same suites at another render rate
(physics always ticks at the project's rate) to check that gameplay behaves
the same on a slow device. A suite whose script holds the line
    ## fps_matrix: 12, 20, 30, 60
runs once per listed rate instead.

The project lint runs first; a violation fails the run, but the suites still
run so both results are visible.
"""

from __future__ import annotations

import argparse
import re
import time
from pathlib import Path

from . import lint
from .godot_env import ensure_class_cache, find_script_errors, reap_stale_headless_godot, run_godot
from .project import Project

FPS_MATRIX_PATTERN = re.compile(r"^##\s*fps_matrix:\s*([0-9][0-9,\s]*)$", re.MULTILINE)


def add_parser(subparsers: argparse._SubParsersAction, parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("test", parents=parents, help="Run test suites headlessly under a watchdog",
                                   description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tests", nargs="*", help="Suite scenes to run (default: every <test dir>/test_*.tscn)")
    parser.add_argument("--fps", type=int, help="Fixed render frame rate (default: test.fps in godot_kit.toml)")
    parser.add_argument("--timeout", type=int, help="Seconds per run (default: test.timeout)")
    parser.add_argument("--verbose", action="store_true", help="Print engine output for passing suites too")
    parser.add_argument("--no-lint", action="store_true", help="Skip the project lint")


def collect_suites(project: Project, paths: list[str]) -> list[str]:
    """Explicit paths as given (project-relative); otherwise every <test dir>/test_*.tscn."""
    if paths:
        return [p.replace("\\", "/").removeprefix("res://") for p in paths]
    folder = project.root / project.test_dir
    return sorted(p.relative_to(project.root).as_posix() for p in folder.glob("test_*.tscn"))


def declared_fps_matrix(project: Project, scene_path: str) -> list[int] | None:
    """Frame rates a suite declares with `## fps_matrix: 12, 20, 60` in its
    script (same path and name as the scene, .gd instead of .tscn), or None."""
    script = project.root / (scene_path[: -len(".tscn")] + ".gd" if scene_path.endswith(".tscn") else scene_path)
    try:
        match = FPS_MATRIX_PATTERN.search(script.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None
    if match is None:
        return None
    rates = [int(value) for value in re.split(r"[,\s]+", match.group(1).strip()) if value]
    return rates or None


def run(args: argparse.Namespace, project: Project) -> int:
    fps_default: int = args.fps or project.config["test"]["fps"]
    timeout: int = args.timeout or project.config["test"]["timeout"]
    lint_ok = True if args.no_lint else lint.run_lint(project)
    if not ensure_class_cache(project):
        return 1
    suites = collect_suites(project, args.tests)
    if not suites:
        print(f"No suites found ({project.test_dir}/test_*.tscn).", flush=True)
        return 1
    missing = [s for s in suites if not (project.root / s).is_file()]
    if missing:
        print(f"Suite(s) not found: {', '.join(missing)}", flush=True)
        return 1
    runs = [(suite, fps) for suite in suites for fps in (declared_fps_matrix(project, suite) or [fps_default])]
    total = len(runs)
    print(f"=== Running {len(suites)} suite{'s' if len(suites) != 1 else ''} as {total} run{'s' if total != 1 else ''} "
          f"(fixed {fps_default} fps unless a suite declares fps_matrix, timeout: {timeout}s/run) ===", flush=True)
    stale = reap_stale_headless_godot()
    if stale > 0:
        print(f"Reaped {stale} leftover headless Godot process(es) from earlier runs.", flush=True)
    started = time.time()
    failed = [failure for index, (suite, fps) in enumerate(runs, 1)
              if (failure := _run_one(project, suite, fps, fps_default, timeout, f"{index}/{total}", args.verbose))]
    return _summarize(total, failed, lint_ok, time.time() - started, fps_default)


def _run_one(project: Project, suite: str, fps: int, fps_default: int, timeout: int, position: str, verbose: bool) -> tuple[str, str] | None:
    """Runs one suite at one frame rate; returns (name, reason) when it failed."""
    display = Path(suite).name if fps == fps_default else f"{Path(suite).name} @ {fps} fps"
    started = time.time()
    output, reason = "", ""
    user_args: list[str] = project.config["test"]["user_args"]
    try:
        result = run_godot(project, ["--headless", "--fixed-fps", str(fps), "--path", ".", suite]
                           + (["--", *user_args] if user_args else []), timeout)
        output = result.output
        errors = find_script_errors(output)
        if result.timed_out:
            reason = f"timed out after {timeout}s"
            # Backstop for kills that cannot reach the engine (WSL interop
            # runs the Windows engine outside Linux's process tree).
            reap_stale_headless_godot(Path(suite).name)
        elif result.returncode != 0:
            reason = f"exit code {result.returncode}"
        elif errors:
            reason = f"{sum(1 for line in errors if not line.startswith('  '))} script error(s)"
    except Exception as error:  # launcher failure (missing binary, etc.)
        reason = f"runner exception: {error}"
    elapsed = time.time() - started
    if not reason:
        print(f"[OK]   [{position}] {display} ({elapsed:.2f}s)", flush=True)
        if verbose:
            print(output, flush=True)
        return None
    print(f"[FAIL] [{position}] {display}: {reason} ({elapsed:.2f}s)", flush=True)
    print(f"----- output of {display} -----\n{output.rstrip()}", flush=True)
    errors = find_script_errors(output)
    if errors:
        print(f"----- script errors in {display} -----\n" + "\n".join(errors), flush=True)
    print(f"----- end of {display} -----", flush=True)
    return (display if fps != fps_default else suite, reason)


def _summarize(total: int, failed: list[tuple[str, str]], lint_ok: bool, elapsed: float, fps: int) -> int:
    print("\n" + "=" * 60, flush=True)
    if not failed:
        print(f"ALL {total} RUNS PASSED ({elapsed:.2f}s total, fixed {fps} fps)", flush=True)
        if not lint_ok:
            print("LINT FAILED: lint violations (see the top of this output).", flush=True)
        print("=" * 60, flush=True)
        return 0 if lint_ok else 1
    print(f"TESTS FAILED: {total - len(failed)}/{total} runs passed, {len(failed)} failed ({elapsed:.2f}s total, fixed {fps} fps)", flush=True)
    print("\nFailures:", flush=True)
    for name, reason in failed:
        print(f"  - {name}: {reason}", flush=True)
    if not lint_ok:
        print("  - lint: violations (see the top of this output)", flush=True)
    print("=" * 60, flush=True)
    return 1

"""Launching Godot for every kit command.

Godot does not exit on script errors, bad preloads or missing autoloads: it
prints the error and idles forever. A run is only safe with a hard watchdog,
and a watchdog only works if the kill really reaches the engine:

- The binary must be the engine itself, not a launcher shim. Killing a Windows
  .cmd/.bat shim (or a *_console.exe wrapper) leaves the engine it started
  running, still holding the output pipes, so a runner reading them blocks
  forever. resolve_godot() unwraps shims and prefers the plain executable.
- run_watched() kills the whole process tree on timeout and never waits on the
  pipes indefinitely, so a surviving descendant cannot hang the runner either.

A project can pin an engine version (godot_kit.toml [engine] version). When
the resolved binary reports another version, a sibling binary of the pinned
version (Godot_v<version>-stable_*) is used if one is installed next to it;
otherwise the command stops instead of running, or importing, the project
with the wrong engine.

Prove the runners after changing this module: kit.py check-runners.
"""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from .project import ConfigError, Project

# Output lines that mean a Godot run is broken even when it exits 0.
SCRIPT_ERROR_MARKERS = ("SCRIPT ERROR:", "Parse Error:", "Compile Error:")
# How long to wait for output readers after the process ended (or was killed).
_READER_GRACE = 5.0
# Seconds allowed for the headless editor import that rebuilds the class cache.
CLASS_CACHE_REFRESH_TIMEOUT = 300.0
# Seconds allowed for `godot --version`.
_VERSION_TIMEOUT = 30.0

_resolved: dict[str, str] = {}


class EngineError(ConfigError):
    """The engine cannot be found, or is not the version the project pins."""


@dataclass
class RunResult:
    """Outcome of a watched run. returncode is None when the watchdog killed it."""

    cmd: list[str]
    returncode: Optional[int]
    stdout: str
    stderr: str
    elapsed: float

    @property
    def timed_out(self) -> bool:
        return self.returncode is None

    @property
    def output(self) -> str:
        return self.stdout + self.stderr


def resolve_godot(project: Project) -> str:
    """The Godot executable for this project: GODOT_BIN, else `godot` on PATH
    (shims unwrapped), checked against the project's pinned version."""
    pinned = str(project.config["engine"]["version"]).strip()
    cache_key = f"{project.root}|{pinned}"
    if cache_key in _resolved:
        return _resolved[cache_key]
    binary = _base_binary()
    if pinned:
        binary = _pinned_binary(binary, pinned)
    _resolved[cache_key] = binary
    return binary


def engine_version(binary: str) -> str:
    """What `binary --version` prints, e.g. "4.7.2.stable.official.abc123" ("" if it fails)."""
    result = run_watched([binary, "--version"], _VERSION_TIMEOUT, Path.cwd())
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return lines[-1] if lines else ""


def version_matches(reported: str, pinned: str) -> bool:
    """True when a reported version ("4.7.2.stable...") is the pinned one ("4.7.2" or "4.7")."""
    reported_parts = _numeric_parts(reported)
    pinned_parts = _numeric_parts(pinned)
    if not reported_parts or not pinned_parts:
        return False
    while len(reported_parts) < len(pinned_parts):
        reported_parts.append(0)  # "4.7.stable" is 4.7.0
    return reported_parts[: len(pinned_parts)] == pinned_parts


def run_watched(
    cmd: list[str],
    timeout: float,
    cwd: Path,
    on_stdout: Optional[Callable[[str], None]] = None,
    on_stderr: Optional[Callable[[str], None]] = None,
) -> RunResult:
    """Runs a command under a hard watchdog and returns everything it printed.

    Output is read line by line on background threads (so a chatty process
    never blocks on a full pipe) and passed to the optional callbacks as it
    arrives. On timeout the whole process tree is killed; the readers then get
    a short grace period and are abandoned if a descendant still holds the
    pipes, so this function always returns shortly after the timeout.
    """
    start = time.time()
    popen_kwargs: dict = {}
    if os.name == "posix":
        popen_kwargs["start_new_session"] = True  # its own group, killed as one
    proc = subprocess.Popen(
        cmd, cwd=str(cwd), shell=False,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", **popen_kwargs,
    )
    stdout_lines: list[str] = []
    stderr_lines: list[str] = []
    readers = [
        threading.Thread(target=_read_lines, args=(proc.stdout, stdout_lines, on_stdout), daemon=True),
        threading.Thread(target=_read_lines, args=(proc.stderr, stderr_lines, on_stderr), daemon=True),
    ]
    for reader in readers:
        reader.start()
    returncode: Optional[int]
    try:
        returncode = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_tree(proc)
        returncode = None
    for reader in readers:
        reader.join(timeout=_READER_GRACE)
    return RunResult(cmd, returncode, "".join(stdout_lines), "".join(stderr_lines), time.time() - start)


def run_godot(
    project: Project,
    engine_args: list[str],
    timeout: float,
    on_stdout: Optional[Callable[[str], None]] = None,
    on_stderr: Optional[Callable[[str], None]] = None,
) -> RunResult:
    """Runs the project's Godot engine with engine_args from the project root, watched."""
    return run_watched([resolve_godot(project), *engine_args], timeout, project.root, on_stdout, on_stderr)


def find_script_errors(output: str) -> list[str]:
    """Output lines that mark a script error, each followed by its location line."""
    lines = output.splitlines()
    found: list[str] = []
    for index, line in enumerate(lines):
        if any(marker in line for marker in SCRIPT_ERROR_MARKERS):
            found.append(line.strip())
            if index + 1 < len(lines) and lines[index + 1].strip().startswith("at:"):
                found.append("  " + lines[index + 1].strip())
    return found


# --- Class cache -------------------------------------------------------------

_CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
_EXTENDS = re.compile(r"^extends\s+(\w+)\s*$", re.M)
_CACHE_ENTRY = re.compile(r'"base": &"(\w*)",\s*"class": &"(\w+)",.*?"path": "res://([^"]+)"', re.S)


def imported_scripts(root: Path) -> list[Path]:
    """Every .gd file Godot imports: skips .godot, .git, .worktrees and any
    folder holding a .gdignore."""
    found: list[Path] = []
    for directory, subdirs, files in os.walk(root):
        here = Path(directory)
        if (here / ".gdignore").exists():
            subdirs[:] = []
            continue
        subdirs[:] = [d for d in subdirs if d not in (".godot", ".worktrees", ".git")]
        found.extend(here / f for f in files if f.endswith(".gd"))
    return found


def stale_class_cache(root: Path) -> list[str]:
    """Global classes where Godot's class cache disagrees with the scripts: a
    class_name that is missing, moved, has another base, or no longer exists.

    A stale cache makes every script using the class fail to parse ("Could not
    find type ..."), and only an editor import rebuilds it (refresh_class_cache()).
    """
    cache = root / ".godot" / "global_script_class_cache.cfg"
    text = cache.read_text(encoding="utf8") if cache.exists() else ""
    cached = {cls: (path, base) for base, cls, path in _CACHE_ENTRY.findall(text)}
    declared: dict[str, tuple[str, str]] = {}
    for script in imported_scripts(root):
        source = script.read_text(encoding="utf8", errors="replace")
        name = _CLASS_NAME.search(source)
        if name is None:
            continue
        base = _EXTENDS.search(source)
        declared[name.group(1)] = (script.relative_to(root).as_posix(), base.group(1) if base else "")
    stale = [cls for cls in cached if cls not in declared]
    for cls, (path, base) in declared.items():
        if cls not in cached or cached[cls][0] != path or (base and cached[cls][1] != base):
            stale.append(cls)
    return sorted(stale)


def refresh_class_cache(project: Project, timeout: float = CLASS_CACHE_REFRESH_TIMEOUT) -> RunResult:
    """Rebuilds Godot's class cache (and imports new assets) with a headless editor import."""
    return run_godot(project, ["--headless", "--path", ".", "--editor", "--quit"], timeout)


def ensure_class_cache(project: Project) -> bool:
    """Refreshes Godot's class cache when it is stale (e.g. after adding,
    renaming or re-basing a class_name). Returns False, with the reason
    printed, when the refresh fails or leaves it stale."""
    stale = stale_class_cache(project.root)
    if not stale:
        return True
    shown = ", ".join(stale[:8]) + (", ..." if len(stale) > 8 else "")
    print(f"[class cache] out of date for {shown}: running a headless editor import ...", flush=True)
    result = refresh_class_cache(project)
    remaining = stale_class_cache(project.root)
    if result.timed_out or remaining:
        reason = "timed out" if result.timed_out else "still out of date for " + ", ".join(remaining)
        print(f"[class cache] refresh failed ({reason}).", flush=True)
        return False
    print(f"[class cache] refreshed in {result.elapsed:.1f}s.", flush=True)
    return True


# --- Leftover processes ------------------------------------------------------

def count_headless_godot(needle: str = "") -> int:
    """Counts running headless Godot processes (optionally whose command line contains needle)."""
    return _headless_godot(needle, kill=False)


def reap_stale_headless_godot(needle: str = "") -> int:
    """Kills headless Godot processes left behind by earlier runs; returns how many.

    Only processes whose command line contains --headless (and needle, when
    given) are touched, so an open editor is left alone. Failures are
    swallowed: this is hygiene, never part of a verdict.
    """
    return _headless_godot(needle, kill=True)


# --- Internals ---------------------------------------------------------------

def _base_binary() -> str:
    override = os.environ.get("GODOT_BIN", "").strip()
    if override:
        return override
    binary = shutil.which("godot") or ""
    if not binary:
        raise EngineError("Godot not found: put `godot` on PATH or set GODOT_BIN to the engine executable.")
    if Path(binary).suffix.lower() in (".cmd", ".bat"):
        match = re.search(r'"([^"]+\.exe)"', Path(binary).read_text(errors="replace"))
        if not match:
            raise EngineError(f"Cannot unwrap the Godot shim {binary}. Set GODOT_BIN to the engine executable.")
        binary = match.group(1)
    return _plain_executable(binary)


def _plain_executable(binary: str) -> str:
    """The engine itself instead of a Windows *_console.exe wrapper, when it sits next to it."""
    path = Path(binary)
    if path.stem.lower().endswith("_console"):
        plain = path.with_name(path.stem[: -len("_console")] + path.suffix)
        if plain.is_file():
            return str(plain)
    return binary


def _pinned_binary(binary: str, pinned: str) -> str:
    reported = engine_version(binary)
    if version_matches(reported, pinned):
        return binary
    folder = Path(binary).parent
    candidates = [p for p in folder.glob(f"Godot_v{pinned}-stable*") if p.is_file() and p.suffix.lower() not in (".zip", ".txt")]
    # Plain executables first: killing a *_console.exe wrapper orphans the engine.
    for candidate in sorted(candidates, key=lambda p: ("_console" in p.name, p.name)):
        if version_matches(engine_version(str(candidate)), pinned):
            print(f"[engine] {binary} is {reported or 'unknown'}; using {candidate} for pinned {pinned}.", flush=True)
            return str(candidate)
    raise EngineError(
        f"This project pins Godot {pinned} (godot_kit.toml [engine] version) but {binary} is "
        f"{reported or 'an unknown version'}, and no Godot_v{pinned}-stable binary sits next to it. "
        "Set GODOT_BIN to the pinned engine."
    )


def _numeric_parts(version: str) -> list[int]:
    parts: list[int] = []
    for piece in version.strip().split("."):
        if not piece.isdigit():
            break
        parts.append(int(piece))
    return parts


def _read_lines(pipe, sink: list[str], callback: Optional[Callable[[str], None]]) -> None:
    try:
        for line in iter(pipe.readline, ""):
            sink.append(line)
            if callback is not None:
                callback(line)
    except (OSError, ValueError):
        pass  # pipe closed under us after a kill
    finally:
        try:
            pipe.close()
        except OSError:
            pass


def _kill_tree(proc: subprocess.Popen) -> None:
    """Kills proc and everything it started."""
    if os.name == "nt":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], shell=False, capture_output=True, timeout=20)
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    try:
        proc.kill()
        proc.wait(timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass


def _headless_godot(needle: str, kill: bool) -> int:
    count = 0
    # Native Linux/macOS processes.
    if shutil.which("pgrep") is not None:
        pattern = "[Gg]odot.*--headless" + (f".*{re.escape(needle)}" if needle else "")
        try:
            found = subprocess.run(["pgrep", "-f", pattern], shell=False, capture_output=True, text=True, timeout=10)
            pids = [p for p in (found.stdout or "").split() if p.isdigit() and int(p) != os.getpid()]
            count += len(pids)
            if kill and pids:
                subprocess.run(["kill", "-9", *pids], shell=False, capture_output=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass
    # Windows, native or through WSL interop (invisible to pgrep there).
    powershell = shutil.which("powershell.exe") or shutil.which("powershell")
    if powershell is not None:
        condition = "$_.Name -like 'Godot*' -and $_.CommandLine -like '*--headless*'"
        if needle:
            condition += " -and $_.CommandLine -like '*%s*'" % needle.replace("'", "''")
        query = "Get-CimInstance Win32_Process | Where-Object { %s }" % condition
        action = "ForEach-Object { Stop-Process -Id $_.ProcessId -Force; 1 }" if kill else "ForEach-Object { 1 }"
        try:
            probe = subprocess.run([powershell, "-NoProfile", "-Command", f"({query} | {action} | Measure-Object).Count"],
                                   shell=False, capture_output=True, text=True, timeout=30)
            digits = (probe.stdout or "").strip().splitlines()
            if probe.returncode == 0 and digits and digits[-1].strip().isdigit():
                count += int(digits[-1].strip())
        except (OSError, subprocess.SubprocessError):
            pass
    return count

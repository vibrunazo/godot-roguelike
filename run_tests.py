#!/usr/bin/env python3
"""Automated Test Runner for Godot Project.

Runs test suites (test/test_*.tscn) headlessly, each in its own Godot process
under an OS watchdog. A suite passes only when Godot exits 0 AND its output
contains no script errors (Godot skips the rest of a function after a script
error instead of failing, so an exit code alone can report a broken suite as
passing).

Frames run back to back at a fixed timestep (--fixed-fps): game time advances
exactly 1/fps per frame without waiting on the wall clock, which is how the
whole suite finishes in about half a minute. Use --fps to run the same suites
at another render rate (physics always ticks at the project's rate), e.g. to
check that gameplay behaves the same on a slow device.

Usage:
    python run_tests.py                              # all suites
    python run_tests.py test/test_audio.tscn         # specific suite(s)
    python run_tests.py --fps 20                     # emulate a 20 fps device
    python run_tests.py --verbose                    # print engine output for passing suites too
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import time

DEFAULT_TIMEOUT = 10  # seconds per suite (suites take ~1s under --fixed-fps)
DEFAULT_FPS = 60
# Output lines that mean a suite is broken even when Godot exits 0.
FAILURE_MARKERS = ("SCRIPT ERROR:", "Parse Error:", "Compile Error:")


def reap_stale_headless_godot() -> int:
    """Best-effort removal of headless Godot processes left behind by earlier runs.

    Timeout kills sometimes fail to reach the engine itself (e.g. under WSL
    interop the Windows process keeps running after its launcher is killed),
    and the leftovers compete for CPU while looking like a hang in later
    runs. Only processes whose command line contains --headless are touched,
    so an open editor is left alone. Returns roughly how many were reaped;
    failures are swallowed because this is hygiene, never part of a verdict.
    """
    reaped = 0
    # Native Linux/macOS headless processes.
    if shutil.which("pgrep") is not None and shutil.which("pkill") is not None:
        try:
            found = subprocess.run(
                ["pgrep", "-c", "-f", "[Gg]odot.*--headless"],
                shell=False, capture_output=True, text=True, timeout=10,
            )
            lines = (found.stdout or "").strip().splitlines()
            if found.returncode == 0 and lines:
                reaped += int(lines[-1])
                subprocess.run(
                    ["pkill", "-f", "[Gg]odot.*--headless"],
                    shell=False, capture_output=True, text=True, timeout=10,
                )
        except Exception:
            pass
    # WSL interop (and native Windows): the engine is a Windows process that
    # pgrep/pkill cannot see, so query it by command line instead.
    powershell = shutil.which("powershell.exe")
    if powershell is not None:
        headless_filter = (
            "Get-CimInstance Win32_Process | Where-Object "
            "{ $_.Name -like 'Godot*' -and $_.CommandLine -like '*--headless*' }"
        )
        try:
            probe = subprocess.run(
                [powershell, "-Command", "(%s | Measure-Object).Count" % headless_filter],
                shell=False, capture_output=True, text=True, timeout=20,
            )
            digits = (probe.stdout or "").strip().splitlines()
            count = int(digits[-1]) if probe.returncode == 0 and digits else 0
            if count > 0:
                reaped += count
                subprocess.run(
                    [powershell, "-Command",
                     "%s | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" % headless_filter],
                    shell=False, capture_output=True, text=True, timeout=20,
                )
        except Exception:
            pass
    return reaped


def find_failure_lines(output: str) -> list[str]:
    """Returns the output lines (with their location line) that mark a script error."""
    lines = output.splitlines()
    found: list[str] = []
    for index, line in enumerate(lines):
        if any(marker in line for marker in FAILURE_MARKERS):
            found.append(line.strip())
            if index + 1 < len(lines) and lines[index + 1].strip().startswith("at:"):
                found.append("  " + lines[index + 1].strip())
    return found


def decode(stream: object) -> str:
    """Normalizes captured output (TimeoutExpired may hold bytes even with text=True)."""
    if stream is None:
        return ""
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return str(stream)


def collect_tests(paths: list[str]) -> list[str]:
    """Explicit paths as given; otherwise every test/test_*.tscn suite."""
    if paths:
        return paths
    return sorted(glob.glob(os.path.join("test", "test_*.tscn")))


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Godot test suites headlessly under a watchdog.")
    parser.add_argument("tests", nargs="*", help="Suite scenes to run (default: test/test_*.tscn)")
    parser.add_argument("--fps", type=int, default=DEFAULT_FPS, help=f"Fixed render frame rate (default: {DEFAULT_FPS})")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help=f"Seconds per suite (default: {DEFAULT_TIMEOUT})")
    parser.add_argument("--verbose", action="store_true", help="Print engine output for passing suites too")
    args = parser.parse_args()

    tests = collect_tests(args.tests)
    if not tests:
        print("No tests found.", flush=True)
        return 1

    total = len(tests)
    print(f"=== Running {total} test suite{'s' if total != 1 else ''} "
          f"(fixed {args.fps} fps, timeout: {args.timeout}s/suite) ===", flush=True)

    stale = reap_stale_headless_godot()
    if stale > 0:
        print(f"Reaped {stale} leftover headless Godot process(es) from earlier runs.", flush=True)

    godot_bin = shutil.which("godot") or "godot"
    start_total = time.time()
    passed = 0
    failed: list[tuple[str, str]] = []

    for idx, test in enumerate(tests, 1):
        test_display = os.path.basename(test)
        t0 = time.time()
        cmd = [godot_bin, "--headless", "--fixed-fps", str(args.fps), "--path", ".", test]
        output = ""
        reason = ""
        try:
            res = subprocess.run(cmd, shell=False, check=False, capture_output=True,
                                 text=True, encoding="utf-8", errors="replace", timeout=args.timeout)
            output = decode(res.stdout) + decode(res.stderr)
            script_errors = find_failure_lines(output)
            if res.returncode != 0:
                reason = f"exit code {res.returncode}"
            elif script_errors:
                reason = f"{sum(1 for l in script_errors if not l.startswith('  '))} script error(s)"
        except subprocess.TimeoutExpired as e:
            output = decode(e.stdout) + decode(e.stderr)
            reason = f"timed out after {args.timeout}s"
            # The timed-out engine often survives the kill (see
            # reap_stale_headless_godot); clear it so the next suite gets a
            # quiet machine instead of competing with a leftover run.
            reap_stale_headless_godot()
        except Exception as e:  # launcher failure (missing binary, etc.)
            reason = f"runner exception: {e}"
        elapsed = time.time() - t0

        if not reason:
            passed += 1
            print(f"[OK]   [{idx}/{total}] {test_display} ({elapsed:.2f}s)", flush=True)
            if args.verbose:
                print(output, flush=True)
            continue

        failed.append((test, reason))
        print(f"[FAIL] [{idx}/{total}] {test_display}: {reason} ({elapsed:.2f}s)", flush=True)
        print(f"----- output of {test_display} -----", flush=True)
        print(output.rstrip(), flush=True)
        script_errors = find_failure_lines(output)
        if script_errors:
            print(f"----- script errors in {test_display} -----", flush=True)
            print("\n".join(script_errors), flush=True)
        print(f"----- end of {test_display} -----", flush=True)

    total_time = time.time() - start_total
    print("\n" + "=" * 60, flush=True)
    if not failed:
        print(f"ALL {passed} TESTS PASSED! ({total_time:.2f}s total, fixed {args.fps} fps)", flush=True)
        print("=" * 60, flush=True)
        return 0
    print(f"TESTS FAILED: {passed}/{total} passed, {len(failed)} failed "
          f"({total_time:.2f}s total, fixed {args.fps} fps)", flush=True)
    print("\nFailures:", flush=True)
    for t, reason in failed:
        print(f"  - {t}: {reason}", flush=True)
    print("=" * 60, flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())

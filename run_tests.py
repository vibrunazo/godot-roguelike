#!/usr/bin/env python3
"""Automated Test Runner for Godot Project.

Runs test suites (*.tscn in test/) headlessly with per-test timeout guardrails.
Usage:
    python run_tests.py                     # Run all test suites in test/*.tscn
    python run_tests.py test/test_audio.tscn # Run a specific test suite
"""

import glob
import os
import shutil
import subprocess
import sys
import time

DEFAULT_TIMEOUT = 20  # seconds per test


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


def main() -> int:
    # Determine test list
    if len(sys.argv) > 1:
        tests = sys.argv[1:]
    else:
        tests = sorted(glob.glob("test/*.tscn"))

    if not tests:
        print("No tests found.")
        return 1

    total = len(tests)
    print(f"=== Running {total} test suite{'s' if total != 1 else ''} (timeout: {DEFAULT_TIMEOUT}s/test) ===")

    stale = reap_stale_headless_godot()
    if stale > 0:
        print(f"Reaped {stale} leftover headless Godot process(es) from earlier runs.")

    start_total = time.time()
    passed = 0
    failed = []

    for idx, test in enumerate(tests, 1):
        test_display = os.path.basename(test)
        print(f"\n>>> [{idx}/{total}] Running {test_display}...")
        t0 = time.time()
        godot_bin = shutil.which("godot") or "godot"
        try:
            res = subprocess.run(
                [godot_bin, "--headless", "--path", ".", test],
                shell=False,
                check=False,
                timeout=DEFAULT_TIMEOUT,
            )
            elapsed = time.time() - t0
            if res.returncode == 0:
                print(f"[OK] {test_display} passed ({elapsed:.2f}s)")
                passed += 1
            else:
                print(f"[FAIL] {test_display} failed with exit code {res.returncode} ({elapsed:.2f}s)")
                failed.append((test, f"Exit code {res.returncode}"))
        except subprocess.TimeoutExpired:
            elapsed = time.time() - t0
            print(f"[TIMEOUT] {test_display} timed out after {DEFAULT_TIMEOUT}s!")
            failed.append((test, f"Timed out after {DEFAULT_TIMEOUT}s"))
            # The timed-out engine often survives the kill (see
            # reap_stale_headless_godot); clear it so the next suite gets a
            # quiet machine instead of competing with a leftover run.
            reap_stale_headless_godot()
        except Exception as e:
            elapsed = time.time() - t0
            print(f"[ERROR] {test_display} encountered exception: {e}")
            failed.append((test, str(e)))

    total_time = time.time() - start_total
    print("\n" + "=" * 60)
    if not failed:
        print(f"ALL {passed} TESTS PASSED! ({total_time:.2f}s total)")
        print("=" * 60)
        return 0
    else:
        print(f"TESTS FAILED: {passed}/{total} passed, {len(failed)} failed ({total_time:.2f}s total)")
        print("\nFailures:")
        for t, reason in failed:
            print(f"  - {t}: {reason}")
        print("=" * 60)
        return 1


if __name__ == "__main__":
    sys.exit(main())

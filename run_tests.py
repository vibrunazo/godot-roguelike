#!/usr/bin/env python3
"""Automated Test Runner for Godot Project.

Runs test suites (*.tscn in test/) headlessly with per-test timeout guardrails.
Usage:
    python run_tests.py                     # Run all test suites in test/*.tscn
    python run_tests.py test/test_audio.tscn # Run a specific test suite
"""

import glob
import os
import subprocess
import sys
import time

DEFAULT_TIMEOUT = 20  # seconds per test


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

    start_total = time.time()
    passed = 0
    failed = []

    for idx, test in enumerate(tests, 1):
        test_display = os.path.basename(test)
        print(f"\n>>> [{idx}/{total}] Running {test_display}...")
        t0 = time.time()
        try:
            res = subprocess.run(
                f"godot --headless --path . {test}",
                shell=True,
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

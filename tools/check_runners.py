"""Self-tests for the Godot runners: they must never hang and never lie.

Run after changing godot_env.py, run_tests.py, run_scratch.py, capture.py or
tools/levels/build_level.py (about half a minute; needs Godot, not a display):

    python tools/check_runners.py

Each check drives a fixture from tools/runner_checks/ through a real runner:
- a scene that never quits must time out, return within its budget, and
  leave no Godot process behind (the shared watchdog, and run_tests.py),
- a -s script stuck before its first frame (where --quit-after cannot help)
  must do the same through run_scratch.py,
- a scene that hits a script error but exits 0 must still fail run_tests.py.
capture.py is not launched here (it needs a display and a GPU); it uses the
same godot_env.run_godot() as the first check.
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from godot_env import count_headless_godot, reap_stale_headless_godot, run_godot  # noqa: E402

FIXTURES = "tools/runner_checks"
TIMEOUT = 3
# Allowed overshoot past the timeout: engine start-up, the kill, and the
# reader grace period (godot_env._READER_GRACE).
SLACK = 12.0


class Checks:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def expect(self, condition: bool, message: str) -> None:
        print(f"  {'ok  ' if condition else 'FAIL'} {message}", flush=True)
        if not condition:
            self.failures.append(message)


def run_runner(args: list[str]) -> tuple[int, str, float]:
    """Runs one of the project's Python runners with an outer safety timeout."""
    start = time.time()
    try:
        result = subprocess.run([sys.executable, *args], cwd=ROOT, shell=False,
                                capture_output=True, text=True, timeout=TIMEOUT + SLACK * 3)
        return result.returncode, result.stdout + result.stderr, time.time() - start
    except subprocess.TimeoutExpired:
        return -1, "the runner itself hung", time.time() - start


def check_leftovers(checks: Checks, label: str) -> None:
    left = count_headless_godot("runner_checks")
    checks.expect(left == 0, f"{label}: no Godot process left behind (found {left})")
    if left:
        reap_stale_headless_godot("runner_checks")


def main() -> int:
    checks = Checks()
    reap_stale_headless_godot("runner_checks")

    print("godot_env.run_godot() on a scene that never quits", flush=True)
    result = run_godot(["--headless", "--path", ".", f"{FIXTURES}/hang_scene.tscn"], TIMEOUT)
    checks.expect(result.timed_out, "the watchdog reports a timeout")
    checks.expect(result.elapsed < TIMEOUT + SLACK, f"it returns within budget ({result.elapsed:.1f}s)")
    check_leftovers(checks, "run_godot")

    print("run_tests.py on a scene that never quits", flush=True)
    code, output, elapsed = run_runner(["run_tests.py", "--no-lint", "--timeout", str(TIMEOUT), f"{FIXTURES}/hang_scene.tscn"])
    checks.expect(code == 1 and "timed out" in output, f"the run fails as a timeout (exit {code})")
    checks.expect(elapsed < TIMEOUT + SLACK * 2, f"it returns within budget ({elapsed:.1f}s)")
    check_leftovers(checks, "run_tests.py")

    print("run_scratch.py on a -s script stuck in _init()", flush=True)
    code, output, elapsed = run_runner(["run_scratch.py", f"{FIXTURES}/hang_script.gd", "--timeout", str(TIMEOUT)])
    checks.expect(code == 124, f"the run exits 124 as a timeout (exit {code})")
    checks.expect(elapsed < TIMEOUT + SLACK * 2, f"it returns within budget ({elapsed:.1f}s)")
    check_leftovers(checks, "run_scratch.py")

    print("run_tests.py on a scene with a script error that exits 0", flush=True)
    code, output, elapsed = run_runner(["run_tests.py", "--no-lint", "--timeout", "10", f"{FIXTURES}/script_error_scene.tscn"])
    checks.expect(code == 1 and "script error" in output, f"the run fails on the script error (exit {code})")

    print(f"\n[check_runners] {'all checks passed' if not checks.failures else f'{len(checks.failures)} check(s) failed'}", flush=True)
    return 1 if checks.failures else 0


if __name__ == "__main__":
    sys.exit(main())

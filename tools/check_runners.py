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
import tempfile
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from godot_env import count_headless_godot, reap_stale_headless_godot, run_godot, stale_class_cache  # noqa: E402

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


_CACHE_ENTRY = """{
"base": &"%s",
"class": &"%s",
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": "res://%s"
}"""


def check_class_cache_detection(checks: Checks) -> None:
    """stale_class_cache() on a throwaway project tree: it must flag a class
    the cache lacks, a re-based class and a deleted one, and nothing else."""
    print("godot_env.stale_class_cache() on a throwaway project", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".godot").mkdir()
        (root / "ignored").mkdir()
        (root / "ignored" / ".gdignore").write_text("")
        (root / "ignored" / "hidden.gd").write_text("class_name Hidden\nextends Node\n")
        (root / "kept.gd").write_text("class_name Kept\nextends Node\n")
        cache = root / ".godot" / "global_script_class_cache.cfg"

        def write_cache(entries: list[tuple[str, str, str]]) -> None:
            cache.write_text("list=[" + ", ".join(_CACHE_ENTRY % e for e in entries) + "]\n")

        write_cache([("Node", "Kept", "kept.gd")])
        checks.expect(stale_class_cache(root) == [], "a matching cache is not stale (ignored folders are skipped)")
        (root / "added.gd").write_text("class_name Added\nextends Kept\n")
        checks.expect(stale_class_cache(root) == ["Added"], "a class missing from the cache is stale")
        write_cache([("Node", "Kept", "kept.gd"), ("Node", "Added", "added.gd"), ("Node", "Gone", "gone.gd")])
        checks.expect(stale_class_cache(root) == ["Added", "Gone"], "a re-based class and a deleted class are stale")


def main() -> int:
    checks = Checks()
    reap_stale_headless_godot("runner_checks")
    check_class_cache_detection(checks)

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

#!/usr/bin/env python3
"""Self-test for godot-agent-kit. Run it after any change to the kit:

    python selftest/run_selftest.py             # lint rules + every command on a sample project
    python selftest/run_selftest.py --capture   # also capture (needs a display, a GPU and ffmpeg)
    python selftest/run_selftest.py --keep      # keep the temp project for inspection

The lint rules are checked in-process against small generated projects: every
rule must fire on its positive case and stay silent on the negative one. Then
sample_project/ is copied to a temp folder, the kit is vendored into it at
addons/godot_kit/, and every command runs against it as an agent would run it:
init, lint, test (suites, fps_matrix, and cases that must fail), scratch,
check-runners and an engine pin mismatch. Needs Godot (GODOT_BIN or `godot` on
PATH); takes about a minute.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
KIT = HERE.parent
sys.path.insert(0, str(KIT))
sys.dont_write_bytecode = True

from cli import lint  # noqa: E402
from cli.project import ConfigError, load_project  # noqa: E402

# Files every generated lint project starts with.
BASE_FILES = {
    "project.godot": 'config_version=5\n\n[autoload]\n\nGameClock="*res://game/clock.gd"\n',
    "game/clock.gd": "## Clock autoload.\nextends Node\n",
}
BASE_CONFIG = """
[lint]
production_dirs = ["game/"]
physics_clock_dirs = ["game/"]
enable = ["print-in-production"]

[[lint.forbidden_references]]
dirs = ["game/ability/"]
names = ["Ship"]
"""
LONG_BODY = "".join(f"\tvar v{i}: int = {i}\n" for i in range(45))

POSITIVE_FILES = {
    "game/a.tscn": '[gd_scene format=3 uid="uid://b123"]\n',
    "game/b.tscn": '[gd_scene format=3 uid="uid://b123"]\n',
    "game/c.tscn": '[gd_scene format=3 uid="uid://zz9"]\n',
    "game/d.tscn": '[gd_scene format=3 uid="uid://c456"]\n\n[ext_resource type="PackedScene" uid="uid://b123" path="res://game/c.tscn" id="1"]\n',
    "game/loads.gd": '## Loads.\nextends Node\n\nvar s: PackedScene = preload("res://game/a.tscn")\n',
    "game/compat.gd": "## Kept for backwards compatibility.\nextends Node\n",
    "game/long.gd": "## Long.\nextends Node\n\n\nfunc long_one() -> void:\n" + LONG_BODY,
    "game/late.gd": "## Late.\nextends Node\n\n\nfunc f() -> void:\n\tpass\n\nconst LATE: int = 1\n",
    "game/undocumented.gd": "## Undocumented export.\nextends Node\n\n@export var x: int = 1\n",
    "game/null_check.gd": "## Null check.\nextends Node\n\n\nfunc f() -> void:\n\tif GameClock:\n\t\tpass\n",
    "game/ability/uses_ship.gd": "## Uses Ship.\nextends Node\n\nvar ship: Ship\n",
    "game/timers.gd": "## Timers.\nextends Node\n\n\nfunc f() -> void:\n\tvar t: Timer = Timer.new()\n\tawait get_tree().create_timer(1.0).timeout\n",
    "game/timer_node.tscn": '[gd_scene format=3]\n\n[node name="T" type="Timer"]\nwait_time = 2.0\n',
    "game/prints.gd": '## Prints.\nextends Node\n\n\nfunc f() -> void:\n\tprint("x")\n',
    "README.md": "See `docs/missing.md`. Built in " + "D:" + "\\docs\\x.\n",
    "test/helper.gd": "extends Node\n",
    "test/test_bad.gd": '## Bad suite.\nextends Node\n\n\nfunc test_x() -> void:\n\tvar k: int = KEY_SPACE\n\tcheck_eq(1.5, 0.2, "tuned")\n',
}

NEGATIVE_FILES = {
    "game/clean.gd": (
        "## Clean code.\nextends Node\n\n## A documented export.\n@export var speed: float = 1.0\n\n\n"
        "func f() -> void:\n"
        "\tif GameClock.get_child_count() > 0:  # GameClock, not a null check\n"
        "\t\tpass\n"
        "\tvar t: Timer = Timer.new()\n"
        "\tt.process_callback = Timer.TIMER_PROCESS_PHYSICS\n"
        "\tawait get_tree().create_timer(1.0, true, true).timeout\n"
        '\tprint_verbose("dev log")\n'
        '\t# print("commented out")\n'
    ),
    "game/ability/clean_ability.gd": "## Never names [Ship] in code.\nextends Node\n\n# Ship is only in comments.\nvar target: Node3D\n",
    "game/physics_timer.tscn": '[gd_scene format=3]\n\n[node name="T" type="Timer"]\nprocess_callback = 0\n',
    "test/.gdignore": "",
    "test/lib/project_suite.gd": 'extends "res://addons/godot_kit/harness/test_suite.gd"\n',
    "test/test_good.gd": (
        '## Good suite.\nextends "res://test/lib/project_suite.gd"\n\nconst TEST_VALUE: float = 0.5\n\n\n'
        'func test_x() -> void:\n\tcheck_eq(TEST_VALUE, TEST_VALUE, "set by the test")\n\tcheck_approx(1.0, 1.0, "one")\n'
    ),
    "test/test_good.tscn": "[gd_scene format=3]\n",
    "README.md": "See `game/clean.gd` and `.scratch/probe.gd`.\n",
}


class Results:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def expect(self, condition: bool, message: str) -> bool:
        print(f"  {'ok  ' if condition else 'FAIL'} {message}", flush=True)
        if not condition:
            self.failures.append(message)
        return condition


def write_tree(root: Path, files: dict[str, str]) -> None:
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


def lint_rules_found(files: dict[str, str], config: str) -> list[lint.Violation]:
    with tempfile.TemporaryDirectory(prefix="kit_lint_") as tmp:
        root = Path(tmp)
        write_tree(root, {**BASE_FILES, **files, "godot_kit.toml": config})
        violations, _ = lint.lint_project(load_project(str(root), None))
        return violations


def check_lint_rules(results: Results) -> None:
    print("lint rules on generated projects", flush=True)
    found = lint_rules_found(POSITIVE_FILES, BASE_CONFIG)
    fired = {v.rule for v in found}
    for rule in lint.RULES:
        results.expect(rule in fired, f"{rule} fires on its positive case")
    timers = [v for v in found if v.rule == "render-clock-timer"]
    results.expect(len(timers) == 3, f"render-clock-timer flags Timer.new(), create_timer() and a Timer node ({len(timers)} found)")
    quiet = lint_rules_found(NEGATIVE_FILES, BASE_CONFIG)
    results.expect(not quiet, "no rule fires on the negative case" + "".join(f"\n      {v.file}:{v.line} [{v.rule}] {v.detail}" for v in quiet))
    default_off = lint_rules_found({"game/prints.gd": POSITIVE_FILES["game/prints.gd"]}, '[lint]\nproduction_dirs = ["game/"]\n')
    results.expect(not default_off, "print-in-production is off unless lint.enable lists it")
    for label, config in (("an unknown key", "[lint]\nproduction_dir = []\n"),
                          ("a wrongly typed value", "[test]\ntimeout = \"ten\"\n"),
                          ("an unknown rule", "[lint]\nenable = [\"no-such-rule\"]\n"),
                          ("a folder without a trailing slash", "[lint]\nproduction_dirs = [\"game\"]\n")):
        try:
            lint_rules_found({}, config)
            results.expect(False, f"{label} in godot_kit.toml is an error")
        except ConfigError:
            results.expect(True, f"{label} in godot_kit.toml is an error")


def build_sample(tmp: Path) -> Path:
    project = tmp / "project"
    shutil.copytree(HERE / "sample_project", project)
    shutil.copytree(KIT, project / "addons" / "godot_kit",
                    ignore=shutil.ignore_patterns(".git", "__pycache__", "selftest"))
    shutil.copytree(HERE / "cases", project / "cases")
    return project


def kit(project: Path, *args: str, timeout: float = 300) -> tuple[int, str]:
    command = [sys.executable, str(project / "addons" / "godot_kit" / "kit.py"), *args]
    try:
        result = subprocess.run(command, cwd=project, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout)
        return result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return -1, f"kit.py {' '.join(args)} hung"


def check_init(results: Results, project: Path) -> None:
    print("kit.py init", flush=True)
    code, output = kit(project, "init", "--dry-run")
    results.expect(code == 0 and "create  AGENTS.md" in output and not (project / "AGENTS.md").exists(), "--dry-run lists files without writing")
    code, output = kit(project, "init")
    expected = ["AGENTS.md", "CLAUDE.md", "GEMINI.md", ".claude/skills/write-test/SKILL.md", ".claude/settings.json",
                "test/.gdignore", "test/lib/project_suite.gd", "test/test_smoke.gd", ".scratch/.gdignore", ".gitignore"]
    missing = [name for name in expected if not (project / name).exists()]
    results.expect(code == 0 and not missing, f"init creates the scaffold (missing: {missing or 'none'})")
    results.expect("keep    godot_kit.toml" in output, "init keeps an existing godot_kit.toml")
    agents = (project / "AGENTS.md").read_text(encoding="utf-8")
    results.expect("{{" not in agents and "Godot Kit Sample" in agents, "init fills the AGENTS.md placeholders")
    code, output = kit(project, "init")
    results.expect(code == 0 and "[init] 0 created" in output, "a second init creates nothing")
    for suite in (HERE / "sample_suites").iterdir():
        shutil.copy(suite, project / "test" / suite.name)


def check_godot_commands(results: Results, project: Path) -> None:
    print("kit.py lint and test on the sample project", flush=True)
    code, output = kit(project, "lint")
    results.expect(code == 0, "the sample project lints clean" + ("" if code == 0 else "\n" + output))
    code, output = kit(project, "test")
    results.expect(code == 0 and "ALL 4 RUNS PASSED" in output, "the smoke suite and the fps_matrix suite (3 runs) pass" + ("" if code == 0 else "\n" + output[-3000:]))
    results.expect("test_mover.tscn @ 12 fps" in output, "fps_matrix runs the suite at 12 fps")
    cases = {"cases/test_fails_check.tscn": "exit code 1", "cases/test_script_error.tscn": "script error",
             "cases/test_leaks_orphan.tscn": "orphan node"}
    for case, marker in cases.items():
        code, output = kit(project, "test", "--no-lint", case)
        results.expect(code == 1 and marker in output, f"{Path(case).stem} fails the run ({marker})")
    code, output = kit(project, "test", "--no-lint", "cases/test_fails_check.tscn")
    results.expect("PASS test_later_test_still_runs" in output, "a failing test does not stop later tests")

    print("kit.py scratch", flush=True)
    code, output = kit(project, "scratch", "cases/scratch_ok.gd", "--timeout", "20", "--", "--level=x")
    results.expect(code == 0 and "SCRATCH_OK speed=5" in output and "clock=true" in output and "--level=x" in output,
                   "a scratch script runs with autoloads and forwarded arguments" + ("" if code == 0 else "\n" + output[-2000:]))
    code, output = kit(project, "scratch", "cases/scratch_extends_node.gd")
    results.expect(code == 1 and "MUST inherit" in output, "a script that cannot run with -s is refused")
    code, output = kit(project, "capture", "test", "test/test_mover.tscn", "--", "--x")
    results.expect(code == 2 and "only `scratch` and `capture scene`" in output, "`capture test` refuses arguments after --")

    print("kit.py check-runners", flush=True)
    code, output = kit(project, "check-runners", timeout=600)
    results.expect(code == 0, "check-runners passes" + ("" if code == 0 else "\n" + output[-3000:]))

    print("engine pin", flush=True)
    pinned = project / ".scratch" / "pinned.toml"
    pinned.write_text('[engine]\nversion = "0.0.1"\n', encoding="utf-8")
    code, output = kit(project, "test", "--no-lint", "--config", str(pinned))
    results.expect(code == 2 and "pins Godot 0.0.1" in output, "a pinned version that is not installed stops the run")


def check_capture(results: Results, project: Path) -> None:
    print("kit.py capture (display, GPU and ffmpeg)", flush=True)
    code, output = kit(project, "capture", "scene", "game/main.tscn", "--scene-camera", "--at", "1")
    shot = project / "movies" / "main_scene.png"
    results.expect(code == 0 and shot.is_file() and _not_blank(shot), "a screenshot through the scene's camera" + ("" if code == 0 else "\n" + output[-2000:]))
    code, output = kit(project, "capture", "scene", "game/main.tscn", "--sheet", "4", "--duration", "2")
    sheet = project / "movies" / "main_sheet.png"
    results.expect(code == 0 and sheet.is_file() and _not_blank(sheet), "a contact sheet of 4 frames" + ("" if code == 0 else "\n" + output[-2000:]))
    # --at=5 after -- belongs to the scene: the capturer still shoots at its own --at.
    code, output = kit(project, "capture", "scene", "cases/capture_stage.tscn", "--scene-camera", "--verbose", "--output", "movies/staged.png", "--", "--tint=red", "--at=5")
    staged = project / "movies" / "staged.png"
    results.expect(code == 0 and "[StageArgs] --tint=red --at=5" in output and "captured at 0." in output and staged.is_file(),
                   "arguments after -- reach the captured scene, not the capturer" + ("" if code == 0 else "\n" + output[-2000:]))
    code, output = kit(project, "capture", "scene", "cases/capture_stage.tscn", "--scene-camera", "--sheet", "2", "--duration", "1",
                       "--output", "movies/staged_sheet.png", "--", "--tint=blue")
    sheet = project / "movies" / "staged_sheet.png"
    results.expect(code == 0 and sheet.is_file(), "the capturer's own options still apply when arguments are forwarded" + ("" if code == 0 else "\n" + output[-2000:]))
    code, output = kit(project, "capture", "scene", "cases/capture_grid.tscn", "--verbose")
    results.expect(code == 0 and "size (30.0," in output, "the automatic framing covers GridMap cells" + ("" if code == 0 else "\n" + output[-2000:]))
    code, output = kit(project, "capture", "test", "test/test_mover.tscn", "--duration", "1")
    video = project / "movies" / "test_mover.mp4"
    results.expect(code == 0 and video.is_file() and video.stat().st_size > 1000, "a test recording as MP4" + ("" if code == 0 else "\n" + output[-2000:]))


def _not_blank(image_path: Path) -> bool:
    """True when the PNG has more than one color (a capture, not a cleared screen)."""
    try:
        from PIL import Image
    except ImportError:
        return image_path.stat().st_size > 2000
    with Image.open(image_path) as image:
        extrema = image.convert("L").getextrema()
        return extrema[1] - extrema[0] > 10


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--capture", action="store_true", help="Also run captures (needs a display, a GPU and ffmpeg)")
    parser.add_argument("--keep", action="store_true", help="Keep the temp project")
    args = parser.parse_args()
    results = Results()
    check_lint_rules(results)
    tmp = Path(tempfile.mkdtemp(prefix="godot_kit_selftest_"))
    try:
        project = build_sample(tmp)
        check_init(results, project)
        check_godot_commands(results, project)
        if args.capture:
            check_capture(results, project)
    finally:
        if args.keep:
            print(f"\nKept the temp project: {tmp / 'project'}", flush=True)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n[selftest] {'all checks passed' if not results.failures else f'{len(results.failures)} check(s) failed:'}", flush=True)
    for failure in results.failures:
        print(f"  - {failure.splitlines()[0]}", flush=True)
    return 1 if results.failures else 0


if __name__ == "__main__":
    sys.exit(main())

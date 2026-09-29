# Godot Roguelite

A 3D top-down action roguelite made with Godot 4.7. It started from the
GameDev.tv Godot 3D roguelite course
([reference repository](https://gitlab.com/GameDevTV/godot-roguelite-hack-n-slash/v1/godot-roguelite))
and now extends it with its own combat, progression, items, enemies and
levels.

Author: vibrunazo
License: CC0

## Requirements

- **Godot 4.7.2** (standard build, Forward+ renderer).
- **Python 3** for the test, scratch and capture runners.
- **FFmpeg** on `PATH`, only for recording videos with `capture.py`.

The runners find Godot through the `GODOT_BIN` environment variable, or the
`godot` command on `PATH`:

```bash
export GODOT_BIN=/path/to/Godot_v4.7.2-stable
```

## Playing

Open the project in Godot 4.7 and run it (the main scene is the menu level),
or run `godot --path .` from the project root.

## Tests and tools

Always launch Godot for tests and scripts through these runners: they add the
watchdog timeouts that keep a stuck engine from hanging your terminal.

```bash
python run_tests.py                               # every test suite
python run_tests.py test/test_jump_action.tscn    # one suite
python run_tests.py --fps 20                      # emulate a slow device
python tools/lint_project.py                      # the project lint alone (runs first in run_tests.py)
python run_scratch.py .scratch/my_check.gd        # a throwaway -s script
python capture.py map Levels/level_1.tscn         # screenshots and video into movies/
python tools/check_runners.py                     # self-test the runners (after changing them)
```

## Documentation

| File | What it holds |
|---|---|
| `AGENTS.md` | Rules for coding agents (and a good summary of the conventions for people) |
| `.claude/skills/*/SKILL.md` | Step-by-step procedures: combat animations, levels, captures, tests, hang debugging |
| `CAPTURE.md` | The capture tool in detail |
| `tools/levels/README.md` | The level-building pipeline |
| `TODO.md` | Open work |
| `docs/reviews/` | Past code reviews (closed), kept as the record of past design decisions |

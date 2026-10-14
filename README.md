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
- **Python 3.11+** for the tooling, [godot-agent-kit](addons/godot_kit/README.md)
  (vendored in `addons/godot_kit/`).
- **FFmpeg** on `PATH`, only for recording videos with `kit.py capture`.

The kit finds Godot through the `GODOT_BIN` environment variable, or the
`godot` command on `PATH` (`godot_kit.toml` pins the version):

```bash
export GODOT_BIN=/path/to/Godot_v4.7.2-stable
```

## Playing

Open the project in Godot 4.7 and run it (the main scene is the menu level),
or run `godot --path .` from the project root.

## Tests and tools

Always launch Godot for tests and scripts through godot-agent-kit: it adds the
watchdog timeouts that keep a stuck engine from hanging your terminal.

```bash
python addons/godot_kit/kit.py test                                  # the lint, then every test suite
python addons/godot_kit/kit.py test test/test_jump_action.tscn       # one suite
python addons/godot_kit/kit.py test --fps 20                         # emulate a slow device
python addons/godot_kit/kit.py lint                                  # the project lint alone
python addons/godot_kit/kit.py scratch .scratch/my_check.gd          # a throwaway -s script (fast-forwarded at 60 fps)
python addons/godot_kit/kit.py scratch .scratch/my_check.gd --fps 0  # the same, paced to real time
python addons/godot_kit/kit.py capture scene Levels/level_1.tscn     # screenshots and video into movies/
python addons/godot_kit/kit.py check-runners                         # self-test the runners
```

The kit is a git subtree of the godot-agent-kit repository: change it there
and pull (`addons/godot_kit/README.md`, "Updating"), never edit it here.

## Documentation

| File | What it holds |
|---|---|
| `AGENTS.md` | Rules for coding agents (and a good summary of the conventions for people) |
| `.claude/skills/*/SKILL.md` | Step-by-step procedures: combat animations, levels, captures, tests, hang debugging |
| `godot_kit.toml` | The kit's configuration: engine pin, lint folders and rules, capture settings |
| `LORE.md` | Game lore, background, humor guidelines and visual style guide |
| `tools/levels/README.md` | The level-building pipeline |
| `TODO.md` | Open work |
| `docs/reviews/` | Past code reviews (closed), kept as the record of past design decisions |

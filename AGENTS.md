# AGENTS.md - godot-agent-kit

This folder is godot-agent-kit: shared agent rules and tooling for Godot
games (README.md explains it).

- **In a game repository (this folder is `addons/godot_kit/`): never edit
  it.** It is vendored with git subtree. A change belongs in the kit
  repository; the game then pulls it (README, "Updating"). Configure the kit
  for the game in the game's `godot_kit.toml` instead.
- **In the kit repository:** after any change, run
  `python selftest/run_selftest.py` (add `--capture` when capture code
  changed; it needs a display). Every check must pass.
  - Keep it generic: no game names, classes or paths outside the templates'
    examples, and no machine-specific absolute paths (games lint them).
  - A new lint rule needs a positive and a negative case in
    `selftest/run_selftest.py`, a one-line reason in `cli/lint.py` `RULES`,
    and a row in the README. Rule IDs are stable: games configure them by
    name.
  - The runners must never hang and never lie: every Godot launch goes
    through `cli/godot_env.py`, and `kit.py check-runners` must pass.
  - Python: 3.11+ standard library only. GDScript: statically typed, `##`
    docstrings, and no `class_name` (the kit adds no global classes).
  - Never run `git commit` or `git push` unless the user explicitly asks.

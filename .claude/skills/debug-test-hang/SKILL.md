---
name: debug-test-hang
description: Use when run_tests.py reports [TIMEOUT], a suite stalls near its end, a run_scratch.py or capture.py run is killed by its watchdog, or a Godot process seems stuck or left behind. Diagnosing hangs and watchdog kills, not preventing them (prevention is AGENTS.md §1).
---

# Diagnosing a timed-out or hung Godot run

## First: suspect the budget, not the game

A run killed by the watchdog can print misleading tree-membership errors
(`get_tree()` is null, `in_tree=false`, a null parent). The engine's own
shutdown produces them; they look exactly like game code evicting the scene,
but no scene change happened. If the log shows no error before the
`[TIMEOUT]` line, assume a budget overrun first:

1. Time the suite alone: `python run_tests.py test/test_<name>.tscn --verbose`.
2. Look for fixed frame-count waits that add up, and for waits on conditions
   that can never become true (they run to their frame budget). Shrink the
   budgets, or wait on a condition that is guaranteed to happen.
3. Remember each suite has a 10 s wall-clock budget, even though game time is
   cheap under `--fixed-fps`.
4. A `run_scratch.py` script killed at its 15 s default is fast-forwarded too
   (`--fixed-fps 60` unless run with `--fps 0`), so it rarely needs more:
   thousands of simulated physics ticks take well under a second. Count the
   frames it awaits and look for a wait that never ends before raising
   `--timeout`. Never reach for `Engine.time_scale` to speed it up (see
   AGENTS.md §1).

## Real hangs

- **A script failed to compile or a preload is missing:** Godot prints the
  error and idles forever. Look for `SCRIPT ERROR`, `Parse Error` or
  `Compile Error` in `--verbose` output.
- **A `-s` script** must `extends SceneTree` and call `quit(code)` on every
  path. `run_scratch.py` checks the first; add `quit()` before every early
  return.
- **A suite stalls about a second before its end:** a scene-changing call
  (`exit_shop()`, `SceneTransition.load_scene_path()`/`load_next_level()`,
  `change_scene_to_file()`) freed the suite mid-run. Move that test last in
  its suite.
- **The game-over menu paused the tree:** waits then never advance game logic.
  Keep test players alive (test-owned huge health) and call
  `UI.resume_game()` in `after_each`.

## Finding where the engine really stopped

Godot's stdout can lag the engine badly on some setups (e.g. a Windows engine
driven from WSL), so reading the log by wall clock can point at the wrong
place. Write flushed marker lines instead: open a file in `user://` with
`FileAccess`, write `Time.get_ticks_msec()` plus a label at each step, and
close it. The last marker is where the engine stopped.

## Leftover engine processes

The shared watchdog (`godot_env.run_watched()`) kills the whole process tree,
and `run_tests.py` also reaps a timed-out suite's engine as a backstop, so a
leftover headless Godot usually means a launcher that bypassed `godot_env.py`.
Leftovers slow every later run. Check the process list
(`tasklist | findstr -i godot` on Windows, `pgrep -a godot` elsewhere). Runners
must launch the real engine binary (`godot_env.resolve_godot()`): killing a
`.cmd` shim orphans the engine, which keeps the output pipes open and hangs
the runner itself. If you suspect a runner, `python tools/check_runners.py`
proves they still time out, clean up and catch script errors.

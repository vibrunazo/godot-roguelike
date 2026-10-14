---
name: write-test
description: Use before creating or changing anything in test/, or when deciding whether a change needs a regression test - when to add one, the harness (test/lib/project_suite.gd on top of the kit's test_suite.gd), fps_matrix, kit.py test, check()/wait_until()/spawn(), and what a permanent regression test may and may not assert.
---

# Writing a test suite

## When to add a test

- **Add one** when you fix a bug, or add or change a mechanic whose behavior
  can regress (a player or designer would call it a bug if it broke). You
  don't need to be asked.
- **Don't add one** for purely visual changes (colors, meshes, VFX, UI layout:
  verify those with `kit.py capture`), for content the existing suites
  already cover (e.g. `test_level_rotation_nav` checks every level), or just to prove to yourself that your change works (use a
  throwaway script in `.scratch/` with `kit.py scratch`).
- **Admission check** for every permanent test: (1) it asserts behavior that
  would be a bug if it broke; (2) it still passes after any exported value is
  retuned, any data file is edited, anything is recolored or remodeled, or any
  key is rebound; (3) it uses only the public API and the harness.
- **Hard rules:**
  - Never assert balance or tuning values, including comparisons between two
    tuned values (set the values the mechanism needs in the test instead).
  - Never assert what a data file (`.tres`, an exported default) contains: a
    designer changing it is not a bug. Build test-owned resources instead.
  - Drive input by `InputMap` action name, never physical keys.
  - Go through the path the game itself uses (AGENTS.md names it): hit things
    through `Hurtbox.receive_hit()` or a real hitbox, never a direct pool
    write; a test of the shortcut passes while the real path is broken.
  - Never touch the player's real save file or settings; point them at a test
    path.
- **When an existing test fails after your change:** if the behavior change
  was intended, update the test and say so in your report; if not, fix the
  code. Never loosen a test just to make it pass.

### Tuning or mechanic?

| Tuning (never a test) | Mechanic (test this) |
|---|---|
| the brute's punch deals 25 damage | a hit deals the live `AttackComponent`'s damage scaled by a test-owned attack stat |
| a fireball costs 20 mana | casting spends the ability's own `cost`, and is refused with less mana |
| the boss hits harder than the brute | full fire resistance (test-owned) cancels fire damage |
| an enemy spawns with 100 health | a character at 0 health is defeated once and emits `defeat` once |

## Start here

- Copy `test/lib/suite_template.gd` to `test/test_<feature>.gd`
  and make a `test/test_<feature>.tscn` with a single `Node` using that
  script. **The rules in the template's header are mandatory**; read them.
- Reference suites: `test/test_character_rotation.gd` (small),
  `test/test_jump_action.gd` (input-driven), `test/test_targeting.gd`.
- Shared fixtures and helpers go in `test/lib/project_suite.gd` (every
  suite extends it); fixture scenes go in `test/fixtures/`. Mechanics
  tests run in a fixture arena, never a real level, so level redesigns never
  break them.
- The header comment lists, one line each, the behaviors the suite protects.

## Harness (`addons/godot_kit/harness/test_suite.gd`)

Every `test_*` method runs in isolation, in declaration order:
`before_each()` -> test -> `after_each()` -> teardown (frees everything the
test spawned and every node added under the suite). A test fails on a failed
check, a script error, or leaked orphan nodes. The suite quits once, with
exit code 1 when anything failed.

- Checks: `check(cond, msg)`, `check_eq()`, `check_approx(actual, expected, msg, tolerance)`,
  `fail(msg)`, `check_no_engine_errors(msg)`. Checks return their result, so
  `if not check(...): return` stops a test whose later steps depend on it.
- Waiting: `wait_until(predicate, msg, max_physics_frames)`,
  `wait_signal(signal, msg, max)`, `wait_physics_frames(n)` (only when the
  frame count itself is what you test), `wait_until_threaded(predicate, msg,
  max_msec)` (for work on other threads, see Pitfalls).
- Nodes: `spawn(scene, parent, position)`, `autofree(node)`.
- This game's helpers (`test/lib/project_suite.gd`): `load_arena()`,
  `arena_floor_top(arena)`, `wait_for_navigation(arena)`,
  `disable_ai(character)`.

**Mechanics tests run in the arena** (`load_arena()`: flat floor, baked
navmesh, `PlayerSpawn`/`EnemySpawn` markers, no enemies, wave or GI). Only
tests about a real level load that level. Regenerate the arena with
`python addons/godot_kit/kit.py scratch test/fixtures/build_arena.gd`; never
hand-edit it.
- Input: `press_action(&"name")`, `hold_action()`, `release_action()`.

## Running

```bash
python addons/godot_kit/kit.py test test/test_<feature>.tscn
python addons/godot_kit/kit.py test test/test_<feature>.tscn --fps 12
python addons/godot_kit/kit.py test
```

Frames run back to back (`--fixed-fps`), so game time is cheap; each run has
a 10 s wall-clock budget. The runner fails a suite on a non-zero exit or any
`SCRIPT ERROR`/`Parse Error`. A suite that must hold at any frame rate
(movement, steering, cooldowns, hit windows) declares
`## fps_matrix: 12, 20, 30, 60` in its script and runs once per rate.

## Prove the test can fail

For every new or rewritten test, break the production code it protects (one
line), run the suite and confirm the test fails with a clear message, then
restore the code. A test that still passes with the mechanism removed tests
nothing: tighten it (for example, set a test-owned value that makes the broken
case observable) or delete it. For a frame-rate bug, the suite must fail at
the rate that shows it (`--fps 30`) before the fix.

## Pitfalls

- `spawn()` sets the position after the node enters the tree, so anything
  that records its position in `_ready()` sees the origin. Instantiate, set
  `position`, then `add_child()` (and `autofree()`) there.
- The test body runs inside a physics frame after an await: Area3D writes are
  deferred there. Wait a tick before reading them.
- `Input.parse_input_event` is flushed per render frame: at low `--fps`
  several physics ticks pass first. Wait on the result, not a tick count.
- AI minds keep thinking while a test drives an actor: stop them (a
  `disable_ai()` helper in `project_suite.gd`).
- The navigation map registers a level asynchronously: wait for
  `map_get_iteration_id() != 0` before querying it.
- Calls that change the scene free the suite about a second later: make that
  test the last one in its suite.
- A paused tree (a game-over or pause menu) stops waits from advancing game
  logic: keep test actors alive with test-owned huge health, and unpause in
  `after_each`.
- Autoload state survives from one test to the next within a suite: reset
  what a test changes in `after_each`.
- Code that deliberately uses wall-clock time (`Time.get_ticks_msec()`,
  `ignore_time_scale` timers) does not follow game time under `--fixed-fps`;
  keep such tests small and separate.
- Work on other threads takes real milliseconds, while fast-forwarded frames
  take microseconds: a `wait_until` frame budget can run out before the thread
  finishes. Wait on it with `wait_until_threaded()`.

## Project pitfalls

- The camera rig records its height floor in `_ready()`: when that height
  matters, instantiate the player, set `position`, then `add_child()` and
  `autofree()` it instead of `spawn()`.
- `WeaponSlot.enabled` is an Area3D write, deferred inside a physics frame:
  wait a tick before reading it.
- The player's `PlayerInputComponent` polls live input and mouse aim: call
  `set_physics_process(false)` on it when the test drives `move_direction` or
  `aim_direction` itself.
- Enemies keep thinking unless `disable_ai(enemy)`; re-enable their
  `ai_state_machine` only in tests about the AI.
- The navigation map registers a level asynchronously: wait for
  `map_get_iteration_id() != 0` before querying it (`wait_for_navigation()`
  does this for the arena).
- `WaveObjective.stop_spawning()` frees the enemies it had planned.
- Calls that change the scene: `exit_shop()`, `load_next_level()`, the main
  menu's Start.
- Player death opens the game-over menu, which pauses the tree: give the
  player test-owned huge health and call `UI.resume_game()` in `after_each`.
- The `NavmeshRebuilder` bakes on a `WorkerThreadPool` thread: wait for it
  with `wait_until_threaded()`.

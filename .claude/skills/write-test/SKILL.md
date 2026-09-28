---
name: write-test
description: Use when writing, migrating, fixing or reviewing a test suite in test/ - the in-house harness (test/lib/test_suite.gd), the arena fixture, fps_matrix, run_tests.py, check()/wait_until()/spawn(), and what a permanent regression test may and may not assert.
---

# Writing a test suite

First decide whether this belongs in `test/` at all (AGENTS.md §3): a
permanent test protects behavior that can regress. To just verify your change,
use `.scratch/` and `run_scratch.py`/`capture.py` instead.

## Start here

- Copy `test/lib/suite_template.gd` to `test/test_<feature>.gd` and make a
  `test/test_<feature>.tscn` with a single `Node` using that script. **The
  rules in the template's header are mandatory**; read them.
- Reference suites: `test/test_character_rotation.gd` (small),
  `test/test_jump_action.gd` (input-driven), `test/test_targeting.gd`.
- The header comment lists, one line each, the behaviors the suite protects.

## Harness (`test/lib/test_suite.gd`)

Every `test_*` method runs in isolation, in declaration order:
`before_each()` -> test -> `after_each()` -> teardown (frees everything the
test spawned and every node added under the suite). A test fails on a failed
check, a script error, or leaked orphan nodes.

- Checks: `check(cond, msg)`, `check_eq()`, `check_approx(actual, expected, msg, tolerance)`,
  `fail(msg)`, `check_no_engine_errors(msg)`. Checks return their result, so
  `if not check(...): return` stops a test whose later steps depend on it.
- Waiting: `wait_until(predicate, msg, max_physics_frames)`,
  `wait_signal(signal, msg, max)`, `wait_physics_frames(n)` (only when the
  frame count itself is what you test).
- Nodes: `spawn(scene, parent, position)`, `autofree(node)`,
  `load_arena()`, `arena_floor_top(arena)`, `wait_for_navigation(arena)`,
  `disable_ai(character)`.
- Input: `press_action(&"name")`, `hold_action()`, `release_action()`.

**Mechanics tests run in the arena** (`load_arena()`: flat floor, baked
navmesh, `PlayerSpawn`/`EnemySpawn` markers, no enemies, wave or GI). Only
tests about a real level load that level. Regenerate the arena with
`python run_scratch.py test/fixtures/build_arena.gd`; never hand-edit it.

## Running

```bash
python run_tests.py test/test_<feature>.tscn          # one suite, 60 fps
python run_tests.py test/test_<feature>.tscn --fps 12  # a slow device
python run_tests.py                                     # everything
```

Frames run back to back (`--fixed-fps`), so game time is cheap; each suite
has a 10 s wall-clock budget. The runner fails a suite on a non-zero exit or
any `SCRIPT ERROR`/`Parse Error`. A suite that must hold at any frame rate
declares `## fps_matrix: 12, 20, 30, 60` in its script.

## Prove the test can fail

For every new or rewritten test, break the production code it protects (one
line), run the suite and confirm the test fails with a clear message, then
restore the code. A test that still passes with the mechanism removed tests
nothing: tighten it (for example, set a test-owned value that makes the broken
case observable) or delete it.

## Pitfalls we hit

- `spawn()` sets the position after the node enters the tree, so anything
  that records its position in `_ready()` (e.g. the camera rig's height floor)
  sees the origin. Instantiate, set `position`, then `add_child()` there.
- The test body runs inside a physics frame after an await: Area3D writes are
  deferred there (e.g. `WeaponSlot.enabled`). Wait a tick before reading them.
- `Input.parse_input_event` is flushed per render frame: at low `--fps`
  several physics ticks pass first. Wait on the result, not a tick count.
- The player's `PlayerInputComponent` polls live input and mouse aim: call
  `set_physics_process(false)` on it when the test drives `move_direction` or
  `aim_direction` itself.
- Enemies keep thinking unless `disable_ai(enemy)`; re-enable their
  `ai_state_machine` only in tests about the AI.
- The navigation map registers a level asynchronously: wait for
  `map_get_iteration_id() != 0` before querying it.
- `WaveObjective.stop_spawning()` frees the enemies it had planned.
- Calls that change the scene (`exit_shop()`, `load_next_level()`, the main
  menu's Start) free the suite about a second later: make that test the last
  one in its suite.
- Player death opens the game-over menu, which pauses the tree: give the
  player test-owned huge health and `UI.resume_game()` in `after_each`.
- Code that deliberately uses wall-clock time (`Time.get_ticks_msec()`,
  `ignore_time_scale` timers) does not follow game time under `--fixed-fps`;
  keep such tests small and separate.

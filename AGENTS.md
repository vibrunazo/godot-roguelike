# AGENTS.md - Rules for every task

Godot 4.7.2 (Forward+) 3D top-down action roguelite, built from the GameDev.tv
Godot 3D course and now extended with our own combat, progression and levels.
We are early in development: **no backwards compatibility**. When a refactor
changes an interface, update its callers; never leave aliases, forwarders or
"legacy" fallbacks behind.

Procedures (adding animations, building levels, capturing media, writing
tests, debugging a timed-out suite) live in skills: see "Skills" at the end.

---

## 1. Running Godot (never hang the terminal)

Godot does not exit on script errors, bad preloads or missing autoloads: it
prints the error and idles forever. `--quit-after` does not help.

- **NEVER run a bare `godot` command.** Always go through a runner with a
  watchdog:
  - `python run_tests.py [test/test_x.tscn ...]` runs the project lint, then
    the suites (`--fps N` emulates a slow device, `--verbose` prints every
    suite's output). Lint alone: `python tools/lint_project.py` (no Godot).
    Every lint violation fails the run; there are no suppressions. Fix the
    code, or the rule if it is wrong. **A red lint is never acceptable**:
    never finish a change that leaves a violation behind.
  - `python run_scratch.py <script.gd> [--timeout N] [--fps N] [-- args]`
    runs a throwaway `-s` script. It must `extends SceneTree`, do its work in
    `_initialize()` (in `_init()` autoloads do not exist yet, so game scripts
    it loads fail to compile) and call `quit(code)`. Its own declarations
    must not use game class types (`var c: Character`): those compile with
    the script, before autoloads exist. Use `Node` and `get()` instead.
  - `python capture.py <map|anim|combat|test> ...` captures screenshots and
    video into `movies/`.
- `run_tests.py` and `run_scratch.py` fast-forward: frames run back to back
  (`--fixed-fps`, 60 by default), so game time is cheap and the simulation is the same as in real
  time. `--fps N` emulates an N fps device; `run_scratch.py --fps 0` paces to
  wall-clock time, only for scripts that measure real time. **Never use
  `Engine.time_scale` to speed a run up:** it lengthens every physics step
  (16x = a 3.75 Hz simulation), which changes results. A scratch script that
  needs more than the default 15 s timeout usually has a bug (a wait that
  never ends, far more frames than intended): find it before raising
  `--timeout`.
- Any new Python launcher must go through `godot_env.run_godot()` (or
  `run_watched()` for other commands): it resolves the engine (`GODOT_BIN`,
  Windows shims unwrapped), streams output, and kills the whole process tree
  at the timeout. Never write another `subprocess` launch of Godot.
- The runners rebuild Godot's class cache themselves when a `class_name` was
  added, moved or re-based (headless editor import); never hand-edit
  `.godot/global_script_class_cache.cfg`.
- After changing `godot_env.py` or a runner, run `python tools/check_runners.py`
  (it proves the runners still time out, clean up and catch script errors).
- A suite that times out: use the `debug-test-hang` skill.

## 2. Code rules

1. **Static typing everywhere.** Every declaration is typed, explicitly
   (`var x: float = 0.0`, `func f(a: int) -> void:`) or by `:=` inference.
   Typed collections (`Array[Node]`, `Dictionary[StringName, float]`) are
   preferred. `untyped_declaration` warnings must stay at zero.
2. **Keep and maintain docstrings** (`## ...`) on classes, exports and
   functions.
3. **No hardcoded asset loads in logic.** Wire scenes and resources through
   `@export` or the `GlobalVars` registry; never `preload()`/`load()` a scene
   as a fallback for a missing export. A required export that is missing is a
   `push_error`, not a silent default.
4. **Reference nodes by typed exports**, not name strings or `get_node` paths,
   wherever the scene can wire them.
5. **Gameplay timing runs on the physics clock** (the game targets slow
   devices): gameplay `AnimationTree`/`AnimationPlayer` use
   `callback_mode_process = PHYSICS`; gameplay `Timer`s use
   `process_callback = PHYSICS`; code timers use
   `get_tree().create_timer(t, true, true)`; gameplay tweens use
   `Tween.TWEEN_PROCESS_PHYSICS`. Purely visual/audio timing may stay on the
   render clock.
6. **Never hand-write resource UIDs** in `.tscn`/`.tres`/`.uid` files. Let
   Godot generate them (open/save via a runner script) or omit the `uid=`.
7. **Parent runtime visuals to the nearest `Node3D`**, never to a plain `Node`
   (it would not inherit the transform).
8. **Balance lives in data** (`.tres` resources, exported properties), never
   in `const` values inside logic.
9. **Autoloads always exist** in game runs: do not null-check them.
10. **Hand-edited `.tscn` files:** the 6-float `AABB(...)` literal does not
    parse there. Leave optional AABB properties (e.g. `visibility_aabb`) out
    instead of writing them.

## 3. Tests and verification

- **Before creating or changing anything in `test/`, read the `write-test`
  skill.** It says when a permanent test is worth adding and how to write one.
- To check your own change, a throwaway script in `.scratch/` (run with
  `run_scratch.py`) is often enough; verify visual changes with `capture.py`.
- Where files go: everything not meant to be committed goes in `.scratch/`
  (git-ignored): throwaway scripts and probes, and the level pipeline's
  intermediates in `.scratch/levels/`. Reusable capture scenarios go in `tools/capture/`, and only
  suites, `test/lib/` and `test/fixtures/` in `test/`.

## 4. Git and workspace

- **Never run `git commit` or `git push`** unless the user explicitly asks.
  The user manages commits.
- Branches, when asked for, go in a worktree under `.worktrees/<branch-name>`
  inside the project. Never create worktrees elsewhere.

## 5. Architecture map

- **Characters** (`Character/character.gd`, a `CharacterBody3D`) are driven by
  two state machines. The **body** `StateMachine` runs `CharacterState`s
  (attacks extend `CharacterAttack`) and owns movement and animation. The
  **mind** is either `PlayerInputComponent` (player) or `AIStateMachine` with
  `AIState`s (enemies). Minds only raise intents (`command_*`) or request body
  states (`order_*`, `StateMachine.request_state()`); body states read only
  the `Character`. Transitions go through `request_state()` or the state's
  `finished` signal. States refer to each other by typed exports, never by
  name strings: an AI state's `body_state` is the body state it orders, and
  `Character.can_accept_order()` is the one rule for when the body takes an
  order.
- **Components** on each character: `AttributeComponent` (health/mana pools,
  buffable stats, tags, timed effects and DoTs; `defeat` fires once on the
  killing transition), `StatusVisualsComponent` (effect visuals, on bones
  when asked), `Hurtbox` (receives hits), `KnockbackComponent`,
  `AirborneTracker` (airborne tag and landing events), `EquipmentComponent`
  (gear and consumables), `PassiveAbilityComponent` (passives triggered by
  ability lifecycle events), `CharacterColorComponent` (palette). Enemies add
  `LootComponent` (gold on defeat); the player adds `TargetingComponent`
  (auto-aim), `ScreenShakeComponent` and `PlayerDefeatHandler` (game over).
  `Character` itself owns the body: movement, facing, intents, orders and
  defeat. Damage types are `DamageType` constants.
- **Damage pipeline:** a `WeaponSlot` (bone attachment) switches its
  `Area3D` hitbox with its `enabled` property, which animations key. The
  hitbox's `AttackComponent` hits `Hurtbox.receive_hit()`, which damages the
  `AttributeComponent` and emits `struck` (stun, flash, shake).
  `damage_pool()`/`restore_pool()` are silent. Lethal hits report `defeat`
  before `struck` reaches handlers, so reaction handlers must ignore the dead.
  `AttackComponent.rehit_interval <= 0` hits a target once per attack;
  `> 0` lets it hit again after that interval.
- **Registries:** `GlobalVars` (items, enemies, dungeons, shared scenes),
  `ProgressionState` (run state: difficulty, dungeon level, gold, purchases,
  the planned encounter and its wave plan, and the player's gear and health:
  each level spawns its own fresh player and `bind_player()` gives it the
  run's gear and health, then records every change), `SceneTransition`
  (fades and level loading), `UI` (HUD, pause and
  game-over menus, fullscreen), `VfxManager`
  (world VFX, damage numbers, the target reticle). All five are autoloads.
- **Levels** inherit `Levels/level_template.tscn` (lighting, wave objective,
  kill plane, exit). `GlobalVars.dungeons` (`DungeonResource`s) is the only
  level registry: `ProgressionState` picks a regular dungeon per encounter,
  or the boss arena whose `boss_at_level` matches the dungeon level.

## 6. Skills

Read the matching file before starting such a task (Claude Code loads them
automatically; other agents follow these paths):

| Task | Skill |
|---|---|
| Adding or wiring a combat animation (`.res`, `AnimationTree`, `WeaponSlot` tracks) | `.claude/skills/add-combat-animation/SKILL.md` |
| Building or editing a level (`GridMap`, navmesh, `VoxelGI`, level rotation) | `.claude/skills/build-level/SKILL.md` |
| Capturing screenshots or video (`capture.py`, `movies/`) | `.claude/skills/capture-media/SKILL.md` |
| Writing, migrating or fixing a test suite (`test/`, harness, arena) | `.claude/skills/write-test/SKILL.md` |
| A suite timed out or a Godot run hung | `.claude/skills/debug-test-hang/SKILL.md` |

Open work is in `TODO.md`. Past code reviews, closed and kept as the record of
why the code looks the way it does, are in `docs/reviews/`.

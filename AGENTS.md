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
  - `python run_tests.py [test/test_x.tscn ...]` runs the suites (`--fps N`
    emulates a slow device, `--verbose` prints every suite's output).
  - `python run_scratch.py <script.gd> [--timeout N] [-- args]` runs a
    throwaway `-s` script (it must `extends SceneTree` and call `quit(code)`).
  - `python capture.py <map|anim|combat|test> ...` captures screenshots and
    video into `movies/`.
- Custom Python launchers must resolve the engine with
  `godot_env.resolve_godot()` (honors `GODOT_BIN`, unwraps Windows shims), use
  `subprocess.run([...], shell=False, timeout=N)` and catch
  `subprocess.TimeoutExpired`. A killed shim leaves the engine running.
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

## 3. Verifying work vs. adding tests

- **Verifying your change is not the same as adding a regression test.** By
  default, verify with a throwaway script or scene in `.scratch/`
  (git-ignored), run through `run_scratch.py` or `capture.py`. Visual changes
  (colors, meshes, VFX, UI layout) are verified with `capture.py`, never with
  suite tests.
- Add or change files in `test/` **only** when the task asks for tests, or
  when you fix a bug or add a mechanic whose behavior can regress. A permanent
  test must: (1) assert behavior a player or designer would call a bug if it
  broke; (2) still pass after any exported value is retuned, anything is
  recolored or remodeled, or any key is rebound; (3) use only the public API
  and the test harness. Use the `write-test` skill.
- **Three hard test rules:** never assert balance or tuning values (including
  comparisons between two tuned values); drive input by `InputMap` action
  name, never physical keys; hit things through `Hurtbox.receive_hit()`, not
  direct pool writes.
- `test/` holds only suites (`test_*.tscn`/`.gd`), `test/lib/` and
  `test/fixtures/`. Throwaway work goes in `.scratch/`; reusable capture
  scenarios in `tools/capture/`; level-pipeline intermediates in
  `tools/levels/out/`.
- If you believe an existing test is wrong, report it instead of weakening it.

### Roles (when the task assigns one)

| Role | May change | Must not |
|---|---|---|
| Test author | `test/`, the harness, fixtures, public interfaces | weaken a test to make it pass |
| Implementer | production code, `.scratch/` | edit `test/`; if a test looks wrong, stop and report it |
| Reviewer | nothing (read-only) | change files; report design and practice problems |

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
  `finished` signal.
- **Components** on each character: `AttributeComponent` (health/mana pools,
  buffable stats, timed effects and DoTs; `defeat` fires once on the killing
  transition), `Hurtbox` (receives hits), `KnockbackComponent`,
  `EquipmentComponent` (gear, consumables, purchase counts),
  `PassiveAbilityComponent` (passives triggered by ability lifecycle events),
  `CharacterColorComponent` (palette), and on the player `ScreenShakeComponent`.
- **Damage pipeline:** a `WeaponSlot` (bone attachment) switches its
  `Area3D` hitbox with its `enabled` property, which animations key. The
  hitbox's `AttackComponent` hits `Hurtbox.receive_hit()`, which damages the
  `AttributeComponent` and emits `struck` (stun, flash, shake).
  `damage_pool()`/`restore_pool()` are silent. Lethal hits report `defeat`
  before `struck` reaches handlers, so reaction handlers must ignore the dead.
  `AttackComponent.rehit_interval <= 0` hits a target once per attack;
  `> 0` lets it hit again after that interval.
- **Registries:** `GlobalVars` (items, enemies, dungeons, shared scenes),
  `ProgressionState` (run state: difficulty, dungeon level, gold, planned
  encounter), `SceneTransition` (level loading, boss arenas, the carried
  player), `UI` (HUD, pause and game-over menus, fullscreen), `VfxManager`
  (world VFX, damage numbers, the target reticle). All five are autoloads.
- **Levels** inherit `Levels/level_template.tscn` (lighting, wave objective,
  kill plane, exit). The run picks levels from `GlobalVars.dungeons`
  (`DungeonResource`s); `SceneTransition.boss_arenas` routes boss levels.

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

Open work is in `TODO.md`; the review behind it and the work plan are in
`CODE_REVIEW.md`.

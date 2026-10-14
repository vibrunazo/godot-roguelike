# AGENTS.md - Rules for every task

{{PROJECT_NAME}}: Godot {{ENGINE_VERSION}} ({{RENDERER}}). <One paragraph: what
the game is, its target platforms and devices, and how far along it is.>
We are early in development: **no backwards compatibility**. When a refactor
changes an interface, update its callers; never leave aliases, forwarders or
"legacy" fallbacks behind.

Procedures (writing tests, capturing media, debugging a timed-out run) live in
skills: see "Skills" at the end. The tooling is godot-agent-kit, vendored in
`{{KIT}}/`: never edit it here (its README says how it is updated).

---

## 1. Running Godot (never hang the terminal)

Godot does not exit on script errors, bad preloads or missing autoloads: it
prints the error and idles forever. `--quit-after` does not help.

- **NEVER run a bare `godot` command.** Always go through the kit, which runs
  Godot under a watchdog:
  - `python {{KIT}}/kit.py test [{{TEST_DIR}}/test_x.tscn ...]` runs the project
    lint, then the suites (`--fps N` emulates a slow device, `--verbose` prints
    every suite's output). Lint alone: `python {{KIT}}/kit.py lint` (no Godot).
    Every lint violation fails the run; there are no suppressions. Fix the
    code, or the rule if it is wrong (`godot_kit.toml`). **A red lint is never
    acceptable**: never finish a change that leaves a violation behind.
  - `python {{KIT}}/kit.py scratch <script.gd> [--timeout N] [--fps N] [-- args]`
    runs a throwaway `-s` script. It must `extends SceneTree`, do its work in
    `_initialize()` (in `_init()` autoloads do not exist yet) and call
    `quit(code)`. Its own declarations must not use game class types
    (`var p: Player`): those compile with the script, before autoloads exist,
    and fail with "Identifier not found" for every autoload. Use `Node` and
    `get()`/`call()` instead.
  - `python {{KIT}}/kit.py capture <scene|test> ...` captures screenshots,
    contact sheets and video into `{{OUTPUT_DIR}}/`.
- The kit fast-forwards: frames run back to back (`--fixed-fps`, 60 by
  default), so game time is cheap and the simulation is the same as in real
  time. `--fps N` emulates an N fps device; `scratch --fps 0` paces to
  wall-clock time, only for scripts that measure real time. **Never use
  `Engine.time_scale` to speed a run up:** it lengthens every physics step
  (16x = a 3.75 Hz simulation), which changes results. A scratch script that
  needs more than the default 15 s timeout usually has a bug (a wait that
  never ends, far more frames than intended): find it before raising
  `--timeout`.
- The engine is `GODOT_BIN`, else `godot` on PATH. `godot_kit.toml` pins its
  version (`[engine] version`), and the kit refuses to run or import the
  project with another one. Never launch Godot from your own `subprocess`
  code: tooling goes through the kit.
- The kit rebuilds Godot's class cache itself when a `class_name` was added,
  moved or re-based (headless editor import); never hand-edit
  `.godot/global_script_class_cache.cfg`.
- A suite that times out: use the `debug-test-hang` skill.

## 2. Code rules

1. **Static typing everywhere.** Every declaration is typed, explicitly
   (`var x: float = 0.0`, `func f(a: int) -> void:`) or by `:=` inference.
   Typed collections (`Array[Node]`, `Dictionary[StringName, float]`) are
   preferred.
2. **Keep and maintain docstrings** (`## ...`) on classes, exports and
   functions.
3. **No hardcoded asset loads in logic.** Wire scenes and resources through
   `@export` or a registry autoload; never `preload()`/`load()` a scene as a
   fallback for a missing export. A required export that is missing is a
   `push_error`, not a silent default.
4. **Reference nodes by typed exports**, not name strings or `get_node` paths,
   wherever the scene can wire them.
5. **Gameplay timing runs on the physics clock** (slow devices render fewer
   frames than physics ticks): code that drives gameplay state each tick
   (movement, steering, cooldowns, AI decisions) runs in `_physics_process`;
   gameplay `AnimationTree`/`AnimationPlayer` use
   `callback_mode_process = PHYSICS`; gameplay `Timer`s use
   `process_callback = PHYSICS`; code timers use
   `get_tree().create_timer(t, true, true)`; gameplay tweens use
   `Tween.TWEEN_PROCESS_PHYSICS`. Purely visual or audio timing may stay on
   the render clock. A mechanic that must hold at any frame rate gets an
   `fps_matrix` suite (see the `write-test` skill).
6. **Never hand-write resource UIDs** in `.tscn`/`.tres`/`.uid` files. Let
   Godot generate them (open and save the file from a scratch script) or omit
   the `uid=`.
7. **Parent runtime visuals to the nearest `Node3D`**, never to a plain `Node`
   (it would not inherit the transform).
8. **Balance lives in data** (`.tres` resources, exported properties), never
   in `const` values inside logic.
9. **Autoloads always exist** in game runs: do not null-check them.
10. **Hand-edited `.tscn` files:** the 6-float `AABB(...)` literal does not
    parse there. Leave optional AABB properties (e.g. `visibility_aabb`) out
    instead of writing them.

## 3. Tests and verification

- **Before creating or changing anything in `{{TEST_DIR}}/`, read the
  `write-test` skill.** It says when a permanent test is worth adding and how
  to write one. Tests assert mechanics, never balance or the contents of data
  files.
- To check your own change, a throwaway script in `.scratch/` (run with
  `kit.py scratch`) is often enough; verify visual changes with
  `kit.py capture`.
- Where files go: everything not meant to be committed goes in `.scratch/`
  (git-ignored), and captures land in `{{OUTPUT_DIR}}/` (git-ignored). Only
  suites, `{{TEST_DIR}}/lib/` and `{{TEST_DIR}}/fixtures/` go in
  `{{TEST_DIR}}/`.

## 4. Git and workspace

- **Never run `git commit` or `git push`** unless the user explicitly asks.
  The user manages commits.
- Branches, when asked for, go in a worktree under `.worktrees/<branch-name>`
  inside the project. Never create worktrees elsewhere.

## 5. Architecture map

<Replace this section with the game's own map, written for an agent that has
never seen the code. What works best:

- Say how the systems connect and which way dependencies point, and name the
  one function that owns each rule ("`Character.can_accept_order()` is the
  one rule for when the body takes an order").
- Say what is data, not code: "a new enemy is a scene with different data,
  not new code".
- Point at a model file to copy for each recurring task ("the Headless Daemon
  is the model for an enemy that casts its own ability").
- Name the public path tests must go through (damage through the hit
  pipeline, not a direct health write), so tests exercise what the game runs.
- Put every dependency rule that can be checked into `godot_kit.toml`
  (`[[lint.forbidden_references]]`), so the lint enforces it.>

## 6. Skills

Read the matching file before starting such a task (Claude Code loads them
automatically; other agents follow these paths):

| Task | Skill |
|---|---|
| Writing, migrating or fixing a test suite (`{{TEST_DIR}}/`, harness, fixtures) | `.claude/skills/write-test/SKILL.md` |
| Capturing screenshots, contact sheets or video (`kit.py capture`) | `.claude/skills/capture-media/SKILL.md` |
| A suite timed out or a Godot run hung | `.claude/skills/debug-test-hang/SKILL.md` |

Open work is in `TODO.md` (open items only; git history keeps the closed
ones). Plans are in `docs/plans/`. Past code reviews, closed and kept as the
record of why the code looks the way it does, are in `docs/reviews/`.

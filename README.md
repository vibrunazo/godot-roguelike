# godot-agent-kit

Ground rules and tooling that keep coding agents, including small local
models, out of the mistakes they make in Godot projects. Extracted from the
godot-roguelite-starting-project, where it was built up over months of agent
work, and shared by every Godot game that vendors it.

What it gives a game:

- **Runners that never hang and never lie.** Godot idles forever on a script
  error; the kit runs it under a watchdog that kills the whole process tree,
  fails a run on any `SCRIPT ERROR` even when Godot exits 0, and proves both
  with `check-runners`.
- **Fast, frame-rate-aware tests.** Frames run back to back (`--fixed-fps`),
  so game time is cheap, and `## fps_matrix: 12, 30, 60` runs a suite at
  several render rates to catch gameplay that breaks on slow devices.
- **A harness that makes the right test the easy one.** Isolated tests,
  soft checks with the failing line, script errors and leaked nodes fail the
  test, waits on conditions, input by action name, exit code set once.
- **A lint with no suppressions.** Every violation prints a one-line reason,
  so an agent gets the fix at the moment it errs. It runs before every test
  run. Dependency rules from AGENTS.md go in config and become enforced.
- **Captures that are cheap to look at.** 768 px screenshots, contact sheets
  of a motion over time, and MP4s of scenes and running suites.
- **Agent docs.** An AGENTS.md skeleton, CLAUDE.md/GEMINI.md pointers, and
  skills for writing tests, capturing media and debugging hangs, with the
  rule that tests assert mechanics, never balance.

## Layout

```
kit.py              entry point: python addons/godot_kit/kit.py <command>
cli/                the commands (Python 3.11+, standard library only)
harness/            test_suite.gd, the base of every suite
capture/            scene and test capturers, screenshot and contact-sheet helpers
runner_checks/      fixtures that prove the runners (hang, script error)
templates/          what `init` copies into a game (AGENTS.md, skills, test/ ...)
selftest/           the kit's own tests and a sample project
```

The whole folder holds a `.gdignore`: Godot never imports it, so nothing here
is exported with the game, and the kit adds no global classes. Suites extend
the harness by path, which works from ignored folders.

## Requirements

- Godot 4.5 or newer (the harness uses the `Logger` API).
- Python 3.11 or newer on PATH as `python`.
- The engine as `GODOT_BIN` or `godot` on PATH (a Windows `.cmd` shim is
  unwrapped to the executable it launches).
- For `capture`: a display, a GPU renderer and `ffmpeg` on PATH.

## Adopting it in a game

The kit must live at `addons/godot_kit/` (suites and capture scenes use that
path). From the game's repository root:

```bash
git subtree add --prefix=addons/godot_kit <path-or-url-of-the-kit-repo> main --squash
python addons/godot_kit/kit.py init
```

`init` creates every missing file and never overwrites one: `AGENTS.md`,
`CLAUDE.md`, `GEMINI.md`, `.claude/skills/{write-test,capture-media,debug-test-hang}`,
`.claude/settings.json` with a hook that installs Godot in cloud sessions,
`godot_kit.toml`, the test folder (`.gdignore`, `lib/project_suite.gd`,
`lib/suite_template.gd`, `test_smoke.tscn`), `.scratch/`, and the lines the kit
needs in `.gitignore`. When the game already has an AGENTS.md, merge §1-§4 of
`templates/AGENTS.md` into it by hand.

Then:
1. Check `godot_kit.toml`: pin `[engine] version`, list `production_dirs`,
   add `physics_clock_dirs` and the dependency rules AGENTS.md states.
2. Write AGENTS.md §5 (the architecture map); the template says what works.
3. `python addons/godot_kit/kit.py lint`, then `... kit.py test`.

## Updating

```bash
git subtree pull --prefix=addons/godot_kit <path-or-url-of-the-kit-repo> main --squash
python addons/godot_kit/kit.py init
```

`init` adds templates that are new; files the game already has are listed as
kept, so compare them with `templates/` by hand. Never edit the kit inside a
game: change the kit repository and pull.

## Commands

Run from the game's project root (`--help` on any command shows every option):

| Command | What it does |
|---|---|
| `kit.py test [suite.tscn ...] [--fps N] [--verbose]` | lint, then each suite in its own headless Godot under a watchdog |
| `kit.py scratch script.gd [--timeout N] [--fps N] [-- args]` | a throwaway `-s` script (`extends SceneTree`, work in `_initialize()`, `quit()`) |
| `kit.py lint` | the project lint, no Godot needed |
| `kit.py capture scene scene.tscn [--scene-camera] [--at S] [--sheet N] [--video] [-- args]` | screenshots, contact sheets, video; arguments after `--` go to the scene (see below) |
| `kit.py capture test test/test_x.tscn` | an MP4 of a suite as it runs |
| `kit.py check-runners` | proves the runners time out, clean up and catch script errors |
| `kit.py init [--dry-run]` | scaffolds the game files above |

Every command takes `--project` and `--config`. Exit codes: 0 success, 1
failure, 2 configuration or engine error, 124 scratch timeout.

**Staging scenes.** A game captures its own setups (a character playing one
animation, a scripted fight) as a scene that `capture scene` runs: arguments
after `--` are forwarded to it, after a `--scene-args` marker in
`OS.get_cmdline_user_args()` that the capturer stops reading at. The scene
reads its arguments there, builds its actors and its camera (run it with
`--scene-camera`), and leaves screenshots, sheets, video and quitting to the
capturer:

```bash
python addons/godot_kit/kit.py capture scene tools/capture/stage.tscn --scene-camera --at 0.5 -- --enemy=brute
```

## godot_kit.toml

Unknown keys and wrong types are errors.

| Key | Default | Meaning |
|---|---|---|
| `engine.version` | `""` | Pinned engine (`"4.7.1"` or `"4.7"`). With another version on PATH, the kit uses `Godot_v<version>-stable*` from the same folder, else stops. |
| `test.dir` | `"test"` | Suites are `<dir>/test_*.tscn`; `<dir>` should hold a `.gdignore`. |
| `test.timeout`, `test.fps` | `10`, `60` | Wall-clock seconds per run; fixed render rate. |
| `test.user_args` | `[]` | User arguments every suite run gets, e.g. `["--save-path=user://test_save.dat"]` so tests never touch the real save. |
| `scratch.timeout`, `scratch.fps` | `15`, `60` | The same for scratch scripts. |
| `lint.production_dirs` | `[]` | Folders of game code (`"characters/"`); production rules only look there. |
| `lint.function_line_limit` | `40` | Longest production function. |
| `lint.test_function_line_limit` | `60` | Longest function in the test folder. |
| `lint.function_line_limits` | `{"tools/" = 80}` | Limits for other folders. |
| `lint.historical_docs` | `["docs/reviews/"]` | Docs allowed to name files that no longer exist. |
| `lint.harness_paths` | kit harness + `res://<test>/lib/project_suite.gd` | What a suite may extend. |
| `lint.assert_functions` | `["check_eq", "check_approx"]` | Assertions checked for tuned float literals. |
| `lint.allowed_load_suffixes` | `[".gdshader", ".gdshaderinc"]` | `res://` paths production code may name. |
| `lint.physics_clock_dirs` | `[]` | Gameplay folders whose timers must run on the physics clock. |
| `lint.forbidden_references` | `[]` | `[[lint.forbidden_references]]` tables: `dirs`, `names`, optional `reason`. |
| `lint.enable`, `lint.disable` | `[]` | Turn rules on or off by ID. |
| `capture.output_dir` | `"movies"` | Where captures land (git-ignored). |
| `capture.hide_paths` | `[]` | Node paths hidden while capturing (`"/root/UI"`). |
| `capture.track_type` | `""` | Class `capture test` keeps in frame (`"Character"`). |
| `capture.screenshot_timeout`, `capture.video_timeout` | `25`, `90` | Watchdog budgets. |

## Lint rules

Every rule is on by default unless marked opt-in. There are no suppression
comments: fix the code, or change the configuration when the rule is wrong
for the game.

| ID | Flags |
|---|---|
| `uid-duplicate` | two files owning the same UID |
| `uid-noncanonical` | a UID Godot would never write (hand-written) |
| `uid-mismatch` | an `ext_resource` UID owned by a different file than its path |
| `hardcoded-load` | a `res://` path in production code |
| `absolute-path` | a machine-specific path in code, scenes, config or docs |
| `test-key-constant` | a `KEY_*` constant in a test (use action names) |
| `test-float-literal` | an assertion against a tuned-looking float literal |
| `test-stray-file` | a file in the test folder that is not a suite, `lib/` or `fixtures/` |
| `test-not-harness` | a suite that does not extend the harness |
| `compat-wording` | "alias", "legacy" or "backward compatible" in a production docstring |
| `missing-reference` | a Markdown doc naming a file that does not exist |
| `long-function` | a function longer than its folder's limit |
| `late-declaration` | a top-level `const` or `@export` after the first `func` |
| `export-undocumented` | an `@export` without a `##` docstring |
| `autoload-null-check` | `if Globals`, `x if Events else y`: autoloads always exist |
| `forbidden-reference` | a folder naming a class it must not depend on (configured) |
| `render-clock-timer` | `Timer.new()` without the physics callback, `create_timer()` without `process_in_physics`, a Timer node on the idle clock (in `physics_clock_dirs`) |
| `print-in-production` | `print()` in production code (opt-in) |

## Developing the kit

```bash
python selftest/run_selftest.py            # every lint rule, then every command on a sample project
python selftest/run_selftest.py --capture  # also captures (needs a display, a GPU, ffmpeg)
```

Every check must pass before a change is done. Keep the kit generic: no game
names, classes or paths outside the templates' examples, and no
machine-specific paths. A new lint rule needs a positive and a negative case
in `selftest/run_selftest.py`, a reason in `cli/lint.py` `RULES` and a row
above; rule IDs are stable because games configure them by name. Every Godot
launch goes through `cli/godot_env.py`.

# Code Review: Practices, Tests, Docs & Tooling

**Date:** 2026-09-23  **Commit reviewed:** `592c549` (master, clean tree)
**Scope:** production GDScript (`Character/`, `Components/`, `Enemy/`, `Hazards/`, `Items/`, `Levels/`, `Passives/`, `Player/`, `Singletons/`, `StateMachine/`, `UserInterface/`), the test suite (`test/`), the Python tooling (`run_tests.py`, `run_scratch.py`, `capture.py`, `tools/levels/`), and all Markdown docs (`AGENTS.md`, `README.md`, `CAPTURE.md`, `TODO.md`, `tools/levels/README.md`).

**Test run during review:** `python run_tests.py` reported **ALL 49 TESTS PASSED (162.8 s)**. But 4 of the 49 are not tests (§3.4.7), and one passing suite logged 24 `SCRIPT ERROR`s that the runner did not catch (§3.4.1). Adding `--fixed-fps 60` to each invocation ran the same 45 real suites to the same result in **34.6 s** (§3.6).

**Phase A done (2026-09-24):** runner hardened, recording scenes moved, Level 10 walls fixed, `WaveObjective` leak fixed, UIDs canonicalized, harness, arena and template added, `test_character_rotation` migrated. §4.4 corrected. Remaining exit leaks come from 7 suites that strip `WaveObjective`'s script (`set_script(null)`); fix them during their Phase B migration.

**Revision 4 (2026-09-24):** §5.5 restructured into phases A–D so the order and the prerequisites are unambiguous.

**Revision 3 (2026-09-24):** severity is shown as text labels (HIGH / MED / LOW) instead of colored markers. Added the frame-rate matrix and mobile performance (§3.9), and scratch vs. suite with agent roles (§5.4).

**Revision 2 (2026-09-24), after follow-up questions:**
- Measured the causes of test slowness (§3.6) and of the leaks (§3.7).
- Added a UID integrity audit (§4.4).
- Checked the duplication claims against behavior, not just line counts (§2.9).
- Replaced third-party tooling with an in-house harness and lint (§3.8, §5.2).
- Added skills to the docs plan (§5.1).
- Merged "fix tests" and "adopt harness" into one step (§5.5, step 4).
- `:=` and typed dictionaries are allowed (§1.2).
- Stale worktrees and branches have been removed by the owner. A leftover `.worktrees/boss-arena-1/` directory (75 MB) is still on disk.

Severity labels are words, not colors: **HIGH** = correctness risk or blocks scaling; **MED** = tech debt that will get worse; **LOW** = cleanup / hygiene. Every finding carries one of these words in its heading or table row.

---

## 0. Executive summary: top 12 actions

| # | Sev | Finding | Section |
|---|-----|---------|---------|
| 1 | HIGH | `test_level_rotation_nav` **passes while throwing 24 SCRIPT ERRORs** (a missing MeshLibrary item 21). `run_tests.py` only checks the exit code, so any error inside a helper counts as a pass. | §3.4.1, §4.2 |
| 2 | HIGH | About 40 test assertions hardcode balance, art or input values (rotation speeds, cooldowns, debug-kill damage, mesh sizes, particle counts, colors, key bindings). These are the tests AGENTS.md forbids. | §3.1–3.3 |
| 3 | HIGH | AGENTS.md describes an architecture that no longer exists (`PlayerState`/`EnemyState`, `ShapeCast3D` hitboxes, screen shake in `AttackComponent`, level rotation via `SceneTransition.levels`). Agents that follow it will make wrong changes. | §1.1 |
| 4 | HIGH | There are **two level registries**: `SceneTransition.levels` (string paths) and `GlobalVars.dungeons` (`DungeonResource`). The rotation test checks the first. The game uses the second, and falls back to the first only when it is empty. | §2.5 |
| 5 | MED | The code has 7+ backward-compat aliases and "legacy" paths, including a typo alias (`movement_speed_ration`) that a test asserts. AGENTS.md explicitly bans these. | §2.6 |
| 6 | MED | 12 hardcoded `load("res://…")` / `preload` fallbacks were added after TODO #8 declared "zero preload/load literals". | §2.7 |
| 7 | MED | `AILeapingDodge._ready()` silently rewrites exported values when they equal the parent's defaults (`trigger_range == 3.5 → 5.0`). This is a sentinel-value trap for designers. | §2.8 |
| 8 | MED | Behavior-checked duplication: the ballistic solver in `FirebombProjectile`/`LobbedSpawnProjectile` is identical, the attack-execution half of `AIAttack`/`AIConditionalAttack` is identical, and the AI "can I order this?" veto is written three times. (The cooldowns turned out to be legitimately per-context; the real issue is who ticks the body cooldown.) | §2.9 |
| 9 | MED | Game logic uses string state names (`"EnemyStun"`, `"EnemyDefeat"`, `"AIPursue"`, …). Renaming a node breaks behavior without any error. | §2.2 |
| 10 | MED | `Character` (824 lines) and `AttributeComponent` (771 lines) are god classes. The generic `StateMachine` knows about `PlayerInputComponent` and the `"click"`/`"jump"` actions. | §2.1, §2.3 |
| 11 | MED | The dev environment is not OS-agnostic: absolute `D:/…` and `C:/Users/…/.gemini/…` paths are committed, worktrees exist outside the repo (including a WSL `/mnt/d` one), and four separate Godot launchers each resolve the binary differently. | §4 |
| 12 | LOW | Test infrastructure is hand-rolled per file: 12+ copies of `_fail`/`check`, a single 3,064-line `_ready()` in `test_enemy_base.gd`, 355 `quit(1)` blocks with manual cleanup, and 70 calls to private `_methods`. | §3.4, §3.8 |
| 13 | HIGH | Tests are slow because headless physics frames are **paced to real time**, not because scenes are heavy. `--fixed-fps 60` makes the suite 4.7× faster overall (up to 16× per suite) with identical results. | §3.6 |
| 14 | MED | **Production leak:** `WaveObjective` instantiates every enemy up front and adds them to the tree one per second. Enemies that haven't spawned when the level unloads (restart, menu, test end) are never freed. This is the source of the exit-time leak spam. | §2.12, §3.7 |
| 15 | MED | **UID drift:** 8 UIDs were hand-written by agents as non-canonical spellings (`uid://d7hurtbox41zq`, …). *(Fixed in Phase A; the "stale reference" part of the original finding was wrong, see §4.4.)* | §4.4 |
| 16 | HIGH | **Hits fail to register at low frame rates.** With physics at 60 Hz, 4–6 suites fail at 30/20/12 render fps, mostly attacks and AoEs that never deal damage. Hitbox windows are driven by idle-mode `AnimationTree`s (one window is 0.030 s). Mid-range phones will run in this range. | §3.9 |
| 17 | HIGH | **Renderer vs. phone target:** every level requires a VoxelGI bake, and VoxelGI is Forward+-only. It isn't available in the Mobile/Compatibility renderers a mid-range phone needs. | §3.9 |
| 18 | MED | Agents add throwaway verification (such as "enemy albedo is orange") to the permanent suite because nothing defines what belongs there. Scratch vs. suite needs a written rule and mechanical enforcement. | §5.4 |

---

## 1. AGENTS.md consistency

### 1.1 [HIGH] AGENTS.md vs. the code (factually stale)

| AGENTS.md says | Reality | Fix |
|---|---|---|
| §4 "States extend `PlayerState` or `EnemyState`." | Neither class exists. Body states extend `CharacterState` (and attacks extend `CharacterAttack`). Mind states extend `AIState` under `AIStateMachine`. | Describe the Body/Mind dual state machine and the base classes that exist. |
| §4 `AttackComponent` "handles screen shake". | Shake lives in `ScreenShakeComponent` (`Components/screen_shake_component.gd:52`). `AttackComponent` only exposes a `shake_on_damage` flag. | Update. |
| §5 track table: "Strike apex: `true` (enables hitbox `ShapeCast3D`)". | Hitboxes are `Area3D` (`WeaponSlot.hitbox`, TODO #1). | Say "enables hitbox `Area3D` monitoring". |
| §6.5 "add its scene path to `SceneTransition.levels` in `res://Singletons/scene_transition.tscn`". | The `.tscn` doesn't override `levels`; the list is the script default (`scene_transition.gd:18`). Level selection actually goes through `GlobalVars.dungeons` → `DungeonResource` (`progression_state.gd:160`, `scene_transition.gd:85`). | Fix after unifying the registries (§2.5). |
| §3 example: `simulate_time(node.cooldown_time)`. | No `simulate_time` helper and no `cooldown_time` property exist. The property is `cooldown`. | Use a real helper name once one exists (§3.5). |
| §3 example: `target.health == previous_health - attack.damage`. | No `.health` property exists. Health is `attribute_component.get_current(AttributeComponent.POOL_HEALTH)`. | Use the real API in examples. Agents copy them literally. |
| §3 example: `"toggle_fullscreen"`. | The action is `ui_toggle_fullscreen` (`project.godot`). | Fix. |
| §2.4 "Avoid hardcoding `preload()` PackedScenes." | 12 violations (§2.7). | Enforce with a lint check (§5). |
| §1 "Do NOT worry about backwards compatibility … refactor the clients." | 7+ compat aliases (§2.6). | Delete them (§2.6). |
| §3 "Never assert balance values"; "never physical key constants (`KEY_F`)". | About 40 violations (§3). | Fix the tests. |
| Worktree rule: only under `.worktrees/<branch>`. | `git worktree list` shows 5 worktrees under `C:/Users/vibru/.gemini/antigravity/worktrees/…` and one prunable `/mnt/d/…` (WSL) path. | Prune them (§4.1). |

### 1.2 [MED] AGENTS.md internal contradictions and duplication

- **Scratch location conflict.** §5 tells agents to put extraction scripts in `tools/levels/out/`. §8 (and CAPTURE.md) say throwaway scripts go in `.scratch/` and that `tools/levels/out/` is *"intended for level-pipeline extraction scripts"*, which an animation extractor is not. Pick one: `.scratch/` for throwaway work, `tools/levels/out/` for pipeline intermediates only.
- **§3 and §7 overlap heavily.** Both list the runners and both explain watchdog/`shell=False`/`timeout`. Keep one "Running Godot" section.
- **§8 repeats CAPTURE.md almost verbatim.** The "Designated Scratch Path" paragraph appears word-for-word in both files, and camera suppression is described twice. AGENTS.md should link to CAPTURE.md in 2–3 lines.
- **Rules vs. suggestions are mixed.** §6 says it holds "lessons learned … rather than rigid rules", but also says "Every level **must** pass …". Separate hard contracts (MUST) from tips.
- **War stories in the rulebook.** "Watchdog-Kill Artifacts", "Suite Hygiene", WSL stdout lag and the Part 11 anecdote are useful troubleshooting notes, not agent rules. They make up about 25% of AGENTS.md. Move them to a `docs/TESTING.md` troubleshooting section and link it.
- **Implementation constants in docs.** "`KnockbackComponent` … Active if magnitude > 1.0" and "`xfade_time = 0.2`" will drift the moment someone tunes them. Document the contract (for example "active while knockback dominates movement"), not the number.
- **"Every variable … must be explicitly typed (`var x: float = 0.0`)"** vs. 24 inferred `:=` declarations. **Decision (owner):** both `:=` inference and typed dictionaries count as static typing and are allowed. Reword the rule to "every declaration must be statically typed, explicitly or by `:=` inference; `untyped_declaration` warnings must be zero", and give both forms as examples. Typed dictionaries (`Dictionary[StringName, float]`) are *encouraged* for new code. The 67 untyped `Dictionary` declarations are fine to leave alone and can be converted when touched.

### 1.3 [LOW] AGENTS.md vs. other docs

- **README.md is wrong about the project.** It says the project follows *"Create a Complete **2D** Roguelike Game"*. AGENTS.md says a 3D course, and the reference repo is the 3D hack-n-slash one. README also has no setup, run or test instructions.
- **CAPTURE.md** hardcodes "Forward+/**D3D12** display server" and says actor cameras use `CameraRoot/ShakeCamera3D` in `Player.tscn`. The file is `Player/player.tscn`, and a `CameraRig3D` was recently added (commit `49b54e0`). Verify that this section still matches.
- **TODO.md is mostly a changelog.** 11 of 13 items are `[RESOLVED]` write-ups that name deleted files (`health_component.gd`, `upgrade_*.tscn`, `UserInterface/upgrade_resource.gd`, `enemy_meander.gd`, …). They also make claims that are now false ("Verified zero `preload(`/`load(` literals remain", "All 14 test suites pass"). Its intro still says "while following the course, we adhere closely to the instructor", but the course is finished. Keep only the open items (#4 `AttackData`, #5 rig decoupling) and the new items from this review. Git history keeps the resolved write-ups, or they can become short ADRs in `docs/adr/`.
- **tools/levels/README.md** is accurate and well structured. It is the best doc in the repo. One fix: it calls `test_level_rotation_nav` "the gate for every level" but doesn't mention that the test only covers `SceneTransition.levels` (§2.5).

---

## 2. Production code: design and practices

### 2.1 [MED] God classes

**`Character/character.gd` (824 lines)** handles at least 11 concerns:

- component discovery
- NavigationAgent auto-tuning
- enemy-head anti-perch physics
- auto-aim targeting
- gameplay-tag forwarding
- airborne lifecycle events
- rotation limiting
- controller intents
- defeat handling
- the **gold economy**: `on_defeat()` awards gold with a hardcoded `5` fallback and a linear scan of `GlobalVars.enemies` by `scene_file_path` (`:781-790`)
- **game-over UI**: `reset_game_state()` (`:668`) doesn't reset anything; it waits `DEFEAT_MENU_DELAY` and calls `UI.show_game_over()`

Suggested split:

- `TargetingComponent`: auto-aim, retarget cooldown, target death tracking.
- `AirborneTracker` (or fold it into a `MovementComponent`): airborne tags and events, head-slide.
- `LootComponent` or `EnemyResource`-driven drop on the enemy's `defeat` signal. `Character` should not know about `ProgressionState`.
- A player-only listener (`PlayerDefeatHandler` or `GameFlow` autoload) that shows the game-over screen when the player's `defeat` fires. Rename the method: `reset_game_state` is misleading.

**`cancel_movement_and_abilities()` (`:726-769`)** reaches into other nodes by hardcoded path and name: `"PlayerInputComponent"`, `"DamageTint"`, `"CameraRoot/ShakeCamera3D"`. It also frees any descendant whose name starts with `"Status"` or contains `"burning"` (`:766-769`), which would free an unrelated node named `StatusBar`. Replace this with a signal (`abilities_cancelled`) or an interface: each component implements `cancel_transient_state()` and `Character` calls it on children that have it. Status VFX are already tracked by `AttributeComponent._effect_vfx`, so `clear_temporary_effects()` should own their cleanup.

**`Components/attribute_component.gd` (771 lines)** holds stats and pools, and also gameplay tags, timed tag effects, DoTs, damage-type resistance mapping, **VFX spawning, skeleton lookup and bone-attachment creation** (`_find_skeleton`, `_find_or_create_bone_slot`). The VFX/bone code should move to a `StatusVisualsComponent` that listens to effect applied/removed signals. Tags could be a small `TagContainer` class. Also:

- Damage types are bare `StringName` literals (`&"physical"`, `&"fire"`) scattered across files, and `resistance_stat_for()` special-cases `fire` with an `if`. Add a `DamageType` constants class (or enum) and a `damage_type → resistance stat` dictionary so a new element needs no code change.
- The docstring for `is_stat()` says "the six buffable stat names", but there are eight (`:145`).
- Adding a stat currently takes a const, an array entry, an `@export base_*`, and a seeding line. Consider a `Dictionary[StringName, float]` of base values, or an `AttributeSet` resource.

### 2.2 [MED] String state names and duplicated veto logic

State transitions and checks are done with string literals:

- `ai_state_machine.gd:94-96`, `ai_conditional_attack.gd:105-107`, `ai_leaping_dodge.gd:53-55`: the **same veto block** (`== "EnemyDefeat" or == "EnemyFall"`, `"EnemyStun" and not can_break_stun`) appears three times.
- `ai_state_machine.gd:108-116`: `alert()` checks `"AIMeander"`, `"AIWait"` and `"AIPursue"` by name.
- `@export var attack_state_name: String = "EnemyAttack"` appears in `ai_attack.gd`, `ai_conditional_attack.gd` and `ai_pursue.gd`. `player_jump_kick.gd:58` uses `get_node_or_null("PlayerAttack")`.

Renaming a node in a `.tscn` silently disables behavior. Recommendations:

1. Replace `attack_state_name: String` with `@export var attack_state: CharacterState`, the same pattern `CharacterState` already uses for `fall_state`/`dash_state`.
2. Make "can this body be ordered?" a single method: `Character.can_accept_order(target_state, can_break_stun) -> bool`, or `State` flags (`@export var blocks_ai_orders: bool`, `@export var is_stun: bool`). Then `AIStateMachine`, `AIConditionalAttack` and `AILeapingDodge` call one function.
3. Replace the `"AIMeander"`/`"AIWait"` check in `alert()` with an `@export var alert_state: AIState` plus an `is_idle` flag on `AIState`.

### 2.3 [MED] Layering violations

- **The generic `StateMachine` knows about the player** (`state_machine.gd:49-60`). `_bridge_action_to_intent()` looks up `PlayerInputComponent` and reads the `"click"`/`"jump"` actions in the base class that `AIStateMachine` also inherits. Its docstring says it exists so *"existing `sm._unhandled_input(...)` drivers"* (tests) keep working. Move input handling into `PlayerInputComponent._unhandled_input`, and have tests drive `input_comp.order_attack()` or `Input.parse_input_event()`.
- **`CharacterAttack` and `PlayerDash` branch on `get_node_or_null("PlayerInputComponent")`** (`character_attack.gd:192, 411`, `player_dash.gd:26`). A shared state should not care who controls it. Let the controller push aim into `character.aim_direction`, and let the state read only `Character`.
- **`AttackComponent._ready()` knows about a subclass consumer**: `if parent is Area3D and not (parent is EnemyProjectile)` (`attack_component.gd:48`). Replace it with an explicit `@export var auto_bind_parent_area: bool = true` that projectiles set to false.
- **Production API added for tests:** `PauseMenu.resume_button` is *"kept for test compatibility"* (`pause_menu.gd:40`), `Character.force_retarget()` is "used by tests", and the `StateMachine` input bridge above exists for the same reason. Tests call `_unhandled_input` 44 times and `_transition_to_next_state` 11 times (70 private calls in total). Tests should use public APIs; if one is missing, add it deliberately.

### 2.4 [LOW] Component discovery boilerplate

`Character._ready()` (`:124-175`) repeats `if x == null: x = get_node_or_null("X")` and then `for child in get_children(): if child is X` for 10+ components. `Hurtbox._resolve_attributes()` does the same thing again. This mixes two policies: explicit `@export` wiring and name-based fallback.

- Pick one policy. For a project written by many agents, prefer **explicit exports plus a validation pass** that `push_error`s on missing required wiring, so misconfigured scenes fail loudly.
- If fallback is kept, write one helper: `static func find_component(owner: Node, type: Script) -> Node`.
- `Character._ready()` wires the weapon hitbox's `AttackComponent` twice: once through `weapon_hitbox` (`:186-191`) and again in the `find_children("*", "AttackComponent")` loop (`:192-195`), which already includes it. The `is_connected` guard checks an *unbound* callable while the code connects a *bound* one, so the guard doesn't express its intent. No duplicate-connect error appeared in the test log, but the first block is redundant. Delete it.
- `add_exception(self)` on every `AttackComponent` (`:189, 193`) adds the `CharacterBody3D`. Hitboxes only detect `Hurtbox` areas, and the wielder's hurtbox is already excluded via `wielder` (`attack_component.gd:75`), so this is dead code.

### 2.5 [HIGH] Duplicated sources of truth

| Data | Owners | Risk |
|---|---|---|
| Level list | `SceneTransition.levels` (script-default `Array[String]`) **and** `GlobalVars.dungeons` (`DungeonResource` `.tres`) | A new level must be added in two places. `test_level_rotation_nav` validates only `SceneTransition.levels`, so a dungeon registered only in `GlobalVars.dungeons` is never validated. |
| Boss arenas | `SceneTransition.boss_arenas` (`{10: "res://…"}` hardcoded in script) | This should be a `DungeonResource` field (for example `boss_at_level`) or its own resource. |
| Difficulty pool | `ProgressionState.build_difficulty_pool()` **and** `WaveObjective.build_difficulty_pool()` (identical bodies) | Balance fixes land in one copy only. |
| Dash cooldown timer | `Character.dash_cooldown`, `PlayerInputComponent.dash_cooldown`, `PlayerDash.dash_cooldown` (overwritten from the input component on every enter) | Three owners for one timer. |
| Auto-aim range | `PlayerInputComponent.auto_aim_range` copied into `Character.auto_aim_range` on `_ready` | Changes to one at runtime are invisible to the other. |
| UI scene refs | `UI.pause_menu_scene/hud_scene/level_title_overlay_scene` **and** `GlobalVars.*_scene` | `UI` is a script autoload (`project.godot`), so its `@export` overrides can never be set. They are dead code. |
| Difficulty scaling | `GlobalVars.difficulty_curve` ("Legacy") **and** `ProgressionState.base_difficulty`/`difficulty_increase_per_level` | Nothing reads the curve, but `test_enemy_base.gd:1578` still requires it to be non-null. |
| Default gold drop | `EnemyResource.gold_drop = 5` **and** `Character.on_defeat` literal `5` | These will drift. |
| heal-percent unit | `item_resource.gd:62` and `:99` both guess the unit with `heal_percent > 1.0` | `heal_percent = 1.0` means 100%, while `1.5` means 1.5%. Pick one unit (0–1 fraction) and document it. |

### 2.6 [MED] Backward-compat aliases (banned by AGENTS.md §1)

| Where | Alias | Action |
|---|---|---|
| `StateMachine/PlayerStates/player_jump.gd:16-34` | `movement_speed`, `movement_ratio`, **`movement_speed_ration` (typo)** → `movement_speed_ratio` | Delete all three. `test_jump_action.gd:633` asserts the typo alias works, so delete that check too. |
| `Player/weapon_slot.gd:29` | `shapecast` → `hitbox` | Delete. |
| `Enemy/enemy_resource.gd:20` | `difficulty` → `difficulty_level` | Delete. |
| `Levels/exit_point.gd:8` | `next_level_path` → `next_scene_path` | Delete. |
| `UserInterface/pause_menu.gd:40` | `resume_button`/`restart_button` forwarders "for test compatibility" | Tests should use `buttons_panel.resume_button`. |
| `StateMachine/character_attack.gd:28, 233, 245, 267` | "legacy `attack_component` export" path next to `weapon_slot` | Migrate the scenes to `weapon_slot` and remove the fallback branch. |
| `Singletons/global_vars.gd:13` | "Legacy difficulty scaling curve" | Delete it and the test that requires it. |

### 2.7 [MED] Hardcoded asset fallbacks (violates AGENTS.md §2.4)

Pattern: `if export == null: export = load("res://…")`. This hides missing scene wiring and pins asset paths in code:

- `akira_boss_throw_riders_attack.gd:30,32` and `akira_boss_summon_helpers_attack.gd:26,28` (also `const LobbedSpawnProjectileClass = preload(...)` at `:7`, which is redundant with `class_name LobbedSpawnProjectile`)
- `firebomb_projectile.gd:55, 230`
- `lightning_bolt_projectile.gd:21, 30`
- `lobbed_spawn_projectile.gd:63`
- `ground_damage_aoe.gd:252`
- `ground_slam_attack.gd:9` (`@export var aoe_scene = preload(...)`) **and** `:70` (a second `load` fallback for the same export)
- `character_color_component.gd:16` (`const PALETTE_SHADER = preload(...)`; acceptable for a shader, but be consistent)

Wire these in the scenes and, in `_ready()`, `push_error` when a required export is null. The `GlobalVars` registry fallback pattern is fine when it's intentional, but fallbacks to hardcoded paths are what AGENTS.md forbids.

### 2.8 [MED] Sentinel-value overrides

`StateMachine/AIStates/ai_leaping_dodge.gd:14-19`:

```gdscript
if attack_state_name == "EnemyAttack":
    attack_state_name = ability_state_name
if is_equal_approx(trigger_range, 3.5):
    trigger_range = 5.0
can_break_stun = false
```

A designer who sets `trigger_range = 3.5` in the inspector gets 5.0. `can_break_stun` is shown as an editable export but is always forced to false. Fix: declare the subclass's own defaults by overriding in the scene, or restructure so the parent's defaults aren't exports the child must fight. Docstrings in this file also embed tuning values ("player distance < 5m", "15.0m default"), which go stale on the first tune.

### 2.9 [MED] Copy-paste families (behavior-checked)

Revision 1 used `difflib` shared-line counts, which include boilerplate and don't prove duplicated *behavior*. In revision 2, each pair was diffed function by function and the differences were read, to separate "same algorithm copied" from "similar shape, different purpose".

| Pair | Line overlap | What the diff shows | Verdict |
|---|---|---|---|
| `firebomb_projectile.gd` ↔ `lobbed_spawn_projectile.gd` | 201/246 | Across the 185 lines covering `_physics_process`, `_get_collision_radius`, `set_target_position`, `initialize_trajectory`, `_find_ground_y`, `_calculate_velocity`, `_on_body_entered` and `_on_area_entered`, the **only** differences are: the damage field name (`damage` vs `area_damage`), the payload scene fallback, a cosmetic tumble rotation, the collision radius constant (0.3 vs 0.4), and what happens on a direct hurtbox hit (damage vs detonate). The trajectory solver, ground raycast and flight integration are byte-identical apart from comments. | **Real behavioral duplication.** A bug fix to the ballistic solve must be made twice today. Extract `BallisticProjectile` with virtual `_on_landed(pos)` / `_on_direct_hit(hurtbox)`, and export the collision radius. |
| `ai_attack.gd` ↔ `ai_conditional_attack.gd` | 121/142 | The shared half (cooldown proxy to the body state, `enter()`, the aim gate in `physics_update`, order-then-finish handling) is behaviorally identical. The differences are legitimate: AIAttack is entered by flow and picks from `next_states` at random, while AIConditionalAttack *preempts* via `evaluate_trigger` (range, min range, stun rules) and has a single `next_state`. | **Partly duplicated.** The execution half should be one base (`AIAttackBase`), with the trigger policy and exit choice in subclasses. The trigger logic is not duplication. |
| `ai_conditional_attack.gd` ↔ `ai_leaping_dodge.gd` | 53 | `AILeapingDodge.evaluate_trigger` re-implements the parent method line for line. The only change is a `target_body_state` fallback to `ability_state_name`. The parent's `get_attack_state()` already reads `ability_state_name` from the subclass through `"ability_state_name" in self` duck typing (`ai_conditional_attack.gd:58-63`). | **Real duplication, plus the base class knowing about its subclass.** Override a `_get_body_state_name()` hook instead. |
| AI veto block (×3) | small | `== attack_state_name or "EnemyDefeat" or "EnemyFall"`, then `"EnemyStun" and not can_break_stun`: the same predicate appears in `AIStateMachine.order_attack`, `AIConditionalAttack.evaluate_trigger` and `AILeapingDodge.evaluate_trigger`. | **Real.** See §2.2. |
| `build_difficulty_pool` (×2) | 14 | Function bodies are identical. | **Real.** See §2.5. |
| `akira_boss_throw_riders_attack.gd` ↔ `akira_boss_summon_helpers_attack.gd` | 43/≈104 | Mostly shared *shape* (exports, delayed spawn timer, fallback loads). They spawn different things for different reasons. | **Not established.** Only the hardcoded fallback loads (§2.7) are clearly bad. Revisit if a third "lobbed spawn" attack appears. |

**Cooldowns: finding revised.** Revision 1 counted "six cooldown implementations", but that was a name scan. On reading them, the semantics differ, and per-context cooldowns are correct:

| Cooldown | Meaning |
|---|---|
| `CharacterAttack.cooldown_timer` | Ability cooldown, owned by the body |
| `AIPursue.cooldown_timer` / `attack_cooldown` | AI re-order throttle while chasing |
| `AbilityLifecyclePassive._cooldown_remaining` | Passive proc limiter |
| `AkiraBossRiders._left/_right_cooldown` | Independent per-rider swings |
| `AIAttack`/`AIConditionalAttack` `cooldown`, `cooldown_timer` | *Not* separate cooldowns: property proxies onto the body state's cooldown, with an `_internal_*` fallback when no body state exists |

What is duplicated is only a 3-line decrement, which doesn't justify a shared class on its own. The real design issue is **ownership of the body cooldown**:
- The body state ticks itself only when the character has no AI (`character_attack.gd:130-133`). Otherwise an AI state ticks it through `has_method("tick_cooldown")` / `"cooldown" in att` duck typing, in both `evaluate_trigger` (while inactive) and `physics_update` (while active).
- No enemy today has two AI states targeting the same body attack (checked across all `Enemy/*.tscn`), so nothing double-ticks. But nothing prevents it either: wiring a second AI state to `EnemyAttack` would halve that cooldown silently.
- **Recommendation:** let `CharacterAttack` always tick its own cooldown in `_physics_process`, and make AI states read-only (`is_on_cooldown()` / `can_activate()`). Drop the proxy properties.

### 2.10 [LOW] Hidden tuning values and magic numbers in logic

Designers can't see or change these in the inspector:

- `character.gd:208-233`: NavigationAgent auto-config (`nav_elevation 0.35`, `radius + 0.3` clamped to `0.6..1.5`, `maxf(1.5, radius + 0.8)`). Make them exports or `const` with names.
- `character.gd:268, 281, 289`: `0.01` lift and `-0.5` fall velocity in head-slide.
- `player_input_component.gd:218, 223`: fallback speed `8.0` and gravity `9.8`. These silently disagree with `AttributeComponent.base_speed` and project gravity if either changes. Read `ProjectSettings.get_setting("physics/3d/default_gravity")` and treat a missing `attribute_component` as an error.
- `player_input_component.gd:230`: the damage tint color and `0.2`/`0.5` values.
- `exit_point.gd:36, 44`: trail color and `"Cuttoff", 0.41`. The shader parameter name is misspelled, and tests assert both the typo and the value.
- `ui.gd:15`: `DEBUG_KILL_DAMAGE = 50.0` as a `const` in the UI singleton. Debug cheats belong in a debug-only autoload or `OS.is_debug_build()`-gated node.
- `core_movement()` (`character_state.gd`): `move_toward(velocity.x, 0.0, speed)` decelerates by `speed` per *frame*, not per second. This depends on frame rate and is effectively an instant stop, so it's likely unintended.

### 2.11 [LOW] Smaller smells

- **32 null checks on autoloads** (`if ProgressionState != null`, `VfxManager.has_method("clear_temporary_effects")`). Autoloads always exist in game runs. The checks make it look like a missing singleton is supported, and they hide real errors.
- **26 `get("prop")` / `has_method()` duck-typing sites**. Examples: `jump_state.get("jump_height")` in `player_input_component.gd:214`, `state.get("uninterruptable")` in `character.gd:682`. Prefer typed casts (`as PlayerJump`) or a declared base-class property.
- **Constants declared mid-file** (`character.gd:520-529, 660-662`). The Godot style guide puts `const` at the top.
- **Duplicate defeat cleanup**: `Hurtbox._on_defeat()` and `Character.on_defeat()` (`:811-816`) both disable the same hurtbox.
- `StateMachine`: `request_state` and `_transition_to_next_state` both do the `has_node` check. `await owner.ready` crashes if `owner` is null (a runtime-built machine).
- `SceneTransition.load_scene_path(path_in, args)`: `args` is never used.
- 6 `print()` calls in production (`ui.gd`, `wave_objective.gd`, `ground_slam_attack.gd`). Use a debug-gated logger.
- `AttackComponent.deal_damage_to` uses `kb != Vector3.ZERO` and `dmg >= 0` as "not provided" sentinels, so a caller can't request zero knockback explicitly.
- Every `AttackComponent` runs `_physics_process` every frame even when idle (`current_time += delta`). Use `Time.get_ticks_msec()`, or enable processing only while the hitbox is monitoring.

### 2.12 [MED] `WaveObjective` leaks unspawned enemies (production bug)

`WaveObjective._ready()` (`Levels/wave_objective.gd:108-117`) calls `generate_wave_enemies()`, which **instantiates every enemy of the wave immediately**. A tween then adds them to the tree one at a time (2.5 s, then 1 s per enemy). An instantiated node that is never added to the tree is an *orphan*: nothing frees it when the level unloads. So any level left before the wave finishes spawning (player death and restart, pause menu to main menu, and every test that loads a level) leaks those enemies and all their RIDs: Jolt bodies and shapes, `NavAgent3D`, materials, viewports.

Measured with a probe scene in `.scratch/timing/leak.gd` that loads `level_template.tscn` and quits after 30 physics frames:

| Teardown | Orphan enemies | ObjectDB leaked | RIDs leaked |
|---|---|---|---|
| `quit()` immediately | 3 | 338 | 80 |
| `queue_free()` the level, flush 3 frames, `quit()` | 3 | 359 | 90 |
| **free the unspawned `all_enemies`**, then as above | 3 → freed | **0** | **0** |

Fix options (either works):
1. Store the planned `EnemyResource` list and **instantiate at spawn time** in `spawn_enemy()`. This is preferred: nothing exists before it's needed, and `all_enemies` holds only live nodes.
2. Keep pre-instantiation, but free unspawned ones in `_exit_tree()`: `for e in all_enemies: if is_instance_valid(e) and not e.is_inside_tree(): e.free()`.

`test_level_rotation_nav`'s 2,870 leaked objects are 13 levels × this same leak.

---

## 3. Test suite review

**Totals:** 45 real suites plus 4 non-test scenes, about 16k lines. Runtime is 163 s serially, and `test_jump_action` takes 18.3 s against the 20 s budget.

### 3.1 [HIGH] Assertions on balance / tuning values (designer changes break tests)

These fail when a designer tunes a value, which AGENTS.md §3 explicitly forbids:

| File:line | Asserts | Replace with |
|---|---|---|
| `test_character_rotation.gd:60-64` | player rotation speed `== 720`, boss `== 90`, default `== 360` | Assert `get_rotation_speed() == attribute_component.get_base(STAT_ROTATION_SPEED)` (seeding works) and `> 0`. The behavior tests later in the file already use the live value. |
| `test_debug_kill.gd:36` | `UI.DEBUG_KILL_DAMAGE == 50.0` | Delete. The later relative-damage check is the real test. |
| `test_akira_boss.gd:1298, 1302, 1429` | throw cooldown `== 30`, starting cooldown `== 30`, summon cooldown `== 20` | Assert `> 0`, and that the ability can't re-trigger before `cooldown` elapses (use the node's own value). |
| `test_character_and_ai.gd:937, 1063` | `desired_angle` default `== 90.0` | Delete, or assert that it's within `(0, 360]`. |
| `test_jump_action.gd:790, 808` | clamped ratio `== 0.2` / `== 1.0` | Use `input_comp.min_forward_jump_ratio` / `max_forward_jump_ratio`. The target offsets at `:781, 797` (`-12.0`, "full range ~10 m") are also derived from current speed/jump height; compute them from `air_time * speed`. |
| `test_health_bar.gd:87` | initial bar `== 100.0` | Compare with the bar's `max_value` or the ratio 1.0. |
| `test_enemy_thunder_mage.gd:390` | hit SFX randomizer `streams_count == 5` | Assert `>= 1`. |
| `test_enemy_base.gd:562` | exit trigger `SphereShape3D.radius == 2.0` | Assert that the shape exists and `radius > 0`. |
| `test_attack_cycle.gd:20`, `test_attack_intents.gd:25`, `test_combo_and_dash_cancel.gd:34` | `create_timer(1.1)`, "spawn repositioning timer (1.0s)" | Wait on the actual condition or signal, or read the production timer's `wait_time`. |

### 3.2 [HIGH] Assertions on art / VFX / layout configuration (scene snapshot tests)

These pin how things look rather than what they do. Artists will break them:

- `test_enemy_base.gd:616-682` (ExitPoint wisp height `10.0`, cylinder radii `2.0`, height `20.0`, cutoff `0.41`, torus particle lifetime `3.0`, preprocess `1.0`, inner radius `0.9`, scale `5.0`), `:1234-1274` (fireball particle `amount 16`, `lifetime 0.25`, emission radius `0.25`, scale `0.25–0.5`, hit lifetime `0.6`), `:2250` (AnimationTree `xfade_time 0.2`), `:2361-2366` (sword radius/height), `:1633, 1687` (`size_flags == 6`).
- `test_akira_boss.gd:307-327`: rider sword `r=0.1 h=2.0`, exact orange albedo `Color(1.0, 0.5058824, 0.0)`, SlashVFX quad `4x2`.
- `test_combo_and_dash_cancel.gd:438-442, 510-514`: SlashVFX `QuadMesh(4,2)`, `position.x == -2.0`, animation easing transitions `0.5`/`2.0`.
- `test_damage_flash_and_shake.gd:217, 229`: damage-number `font_size 32`, `outline_size 4`, `scale 1.5`.
- `test_dungeon_progression_and_trail.gd:170, 188`: `Cuttoff == 0.41`.
- `test_character_recolor.gd:49, 107`: exactly `6` body meshes per enemy. Adding a hat mesh breaks it.
- `test_attributes.gd:698`: status VFX `position.y == 0.6`.

**Guideline:** a test may assert that a node exists, what type it is, how it's wired, and *relations* between values ("rider sword matches the melee sword": compare the two resources, not literals; "hit particles are one-shot"). It should not assert magnitudes. Where "looks the same as the player" is the real requirement, compare against the player's live value.

### 3.3 [HIGH] Physical key assertions (forbidden by AGENTS.md §3)

- `test_debug_kill.gd:28, 110`: `KEY_K`
- `test_pause_menu.gd:22-35, 262`: `KEY_P`, `KEY_ESCAPE` (plus a message quoting scancodes `80`/`4194305`)
- `test_jump_action.gd:34-47`: `KEY_SHIFT` (left), `KEY_SPACE`

Replace with `InputMap.has_action("…")` and `not InputMap.action_get_events("…").is_empty()`, and drive input with an `InputEventAction` rather than a synthesized key event.

### 3.4 Structural problems

1. [HIGH] **Runner ignores engine errors.** `run_tests.py` checks only the exit code. In this review's run, `test_level_rotation_nav.tscn` logged **24 `SCRIPT ERROR: Cannot call method 'get_aabb' on a null value`** from `_floor_cell_box` (`test_level_rotation_nav.gd:311`) and **48 `Requested for nonexistent MeshLibrary item '21'`** errors while verifying pit lining (they appear during the `level_10` checks). It still printed `[OK]`. GDScript aborts the failing call and continues, so the pit-lining check silently doesn't run for those cells. Two fixes are needed:
   - `run_tests.py` should capture output and fail on `SCRIPT ERROR` / `Parse Error` / `ERROR:` lines. `tools/levels/build_level.py:39` already does this.
   - Investigate the Wallmap cell that uses item 21 (a level-data bug or a helper that assumes the wrong library), and null-check `get_item_mesh()` in the helper.
2. [MED] **No shared test harness.** Each suite re-implements `_fail`/`check`/`_assert` (12+ variants), and failure handling is inline `printerr(...)`, then `x.queue_free()` ×N, then `get_tree().quit(1)`, then `return` (**355 times** in `test_enemy_base.gd` alone). Consequences:
   - The first failure hides all later ones (fail-fast only).
   - Cleanup is copy-pasted and often incomplete: 33 runs leak ObjectDB instances at exit.
   - There's no per-part timing or summary.

   **Decision (owner):** an in-house base class, not GUT/gdUnit4. It fits the watchdog runners and gives agents one small API to learn. See §3.8 for the spec.
3. [MED] **`test_enemy_base.gd` is one 3,064-line `_ready()` function.** Its parts are named after course lectures ("Lecture 81–86"), not features, parts 14–27 are missing, and Part 11 is deferred to the end because it changes the scene. Split it into feature suites (`test_exit_point`, `test_upgrade_shop`, `test_projectile`, `test_melee_team_filtering`, …), with one function per part as `test_character_and_ai.gd` already does.
4. [MED] **Private API use.** 70 calls to `_underscore` methods (`_unhandled_input` ×44, `_transition_to_next_state` ×11, `_get_default_enemy_resources` ×5, …). These lock production internals in place and justified the input bridge in `StateMachine` (§2.3).
5. [MED] **Fixed-duration waits.** 182 `for i in range(N): await physics_frame` loops and about 20 wall-clock `create_timer(x)` waits. Most loops `break` on a condition, which is fine, but N itself encodes animation lengths. A shared `await wait_until(func() -> bool: ..., max_frames)` helper that fails with a message on timeout would remove the silent fall-through risk and the boilerplate. Timed waits that mirror production timings (1.1 s for a 1.0 s spawn timer) should read the production timer.
6. [MED] **Tests depend on shipped levels and on the template's live wave.** 21 suites load `level_template.tscn`, and several load `level_1/2/3/13`. The template's `WaveObjective` spawns *random* enemies on a timer, and tests have to fight that: `TestUtils.clear_lock_and_hold_facing()` exists because "level enemies wander into auto-aim range", and `TestUtils.find_dummy()` reaches into `WaveObjective.all_enemies` and force-spawns one. **A barebones arena fixture (`test/fixtures/arena.tscn`)** should have a static floor, a baked minimal navmesh, a player, no `WaveObjective`, no VoxelGI and no exit, and tests should spawn exactly the enemies they need. The payoff is **determinism and isolation, not speed**: measured load time is 61 ms for the template vs. 55 ms for a bare floor plus player, and 120 frames cost 42 ms vs. 33 ms under `--fixed-fps` (§3.6). Level-specific suites (rotation/nav, level 13 stairs, brute pit-corner nav) should keep loading real levels, because that is what they test.
7. [LOW] **Non-tests in `test/`.** `capture_firebomber`, `record_brute_attacks`, `record_brute_slam` and `record_fire_traps` are recording scripts. `run_tests.py` globs `test/*.tscn`, so they run as "passing tests" (4 of the 49), and `record_fire_traps.gd:69` writes to `D:/docs/…/movies/`. Move them to `tools/capture/scenarios/`, or delete them since `capture.py` covers these cases.
8. [LOW] **`TestUtils` has both `class_name` and `const TestUtils = preload(...)`.** `test/` is `.gdignore`d, so the `class_name` never registers (CAPTURE.md warns about exactly this). Drop the `class_name` or move shared helpers to an importable `test/lib/`. `TestUtils.find_dummy()` also duck-types `WaveObjective` (`"all_enemies" in wave_obj`, `has_method("spawn_enemy")`) even though the class is known.
9. [LOW] **Stale messages.** Pass messages print literal values ("speed 14.0", "rehit_interval = 0.32s" comments). They don't fail, but they mislead after tuning. Print the live value.

### 3.5 Good patterns to copy

- `test_attributes.gd`: builds its own component, sets its own bases (`200.0`, `10.0`) and asserts formulas (`base_max * (1.0 + buff)`). This is the correct way to test math with concrete numbers.
- `test_enemy_thunder_mage.gd:294, 334`: movement is checked against `speed * delta`, and damage against `flight_bolt.damage`.
- `test_attack_aiming.gd:168-179`: `initial_health - attack_state.damage`.
- `test_enemy_brute.gd:235-237`: sets `cooldown_timer = 2.0`, ticks `0.5`, expects `1.5`. The test owns every value.
- `test_self_hitstop.gd:65-73`: writes a sentinel value, checks for isolation, restores.
- `test_character_and_ai.gd`: one function per part and a readable `_ready()` orchestrator.

### 3.6 [HIGH] Why the suite is slow (measured)

A probe scene (`.scratch/timing/timing.gd`) measured load time plus 120 `physics_frame` awaits plus 120 `process_frame` awaits, headless, on this machine:

| Scene | Load | 120 physics frames | 120 process frames |
|---|---|---|---|
| empty `Node3D` | 49 ms | **1,939 ms** | 861 ms |
| floor + `player.tscn` | 56 ms | **1,933 ms** | 870 ms |
| full `level_template.tscn` | 63 ms | **1,940 ms** | 873 ms |
| *same, with `--fixed-fps 60`* | | | |
| empty | 48 ms | 0 ms | 1 ms |
| floor + player | 55 ms | 33 ms | 32 ms |
| full template | 61 ms | 42 ms | 42 ms |

**Headless Godot paces physics ticks to wall-clock time** (60 Hz means 16.7 ms per tick, however cheap the frame is). Scene weight is noise. A suite with 1,000 physics-frame awaits costs at least 17 s just waiting. `--fixed-fps 60` keeps `delta` at exactly 1/60 but runs frames back to back, so game time (physics, `SceneTreeTimer`, tweens, animations) advances as fast as the CPU allows.

Full-suite result with `--fixed-fps 60` added to each invocation (`.scratch/timing/run_fixed.py`): **45/45 real suites pass, 34.6 s total vs. 163 s**, and nearly every suite sits at the ~0.73 s engine-startup floor:

| Suite | Real time | `--fixed-fps` |
|---|---|---|
| `test_jump_action` | 18.3 s | 1.1 s |
| `test_akira_boss` | 13.6 s | 1.0 s |
| `test_combo_and_dash_cancel` | 9.4 s | 0.9 s |

Output line counts were identical with and without the flag, so the suites do the same work rather than exiting early. What remains is per-process startup, so `-j N` parallelism (§4.3) is now the next multiplier.

Consequences:
- Add `--fixed-fps 60` to `run_tests.py` and to `capture.py test`. The capture pipeline already implies fixed stepping through `--write-movie`.
- The 20 s per-suite budget can drop to about 10 s, which also makes real hangs fail faster.
- AGENTS.md's frame-budget paragraph is **inverted** on this machine: it claims idle/process frames are "far slower than physics frames", but here 120 process frames took 0.86 s and 120 physics frames took 1.94 s. With `--fixed-fps` the distinction disappears, so replace the paragraph with "the runner uses `--fixed-fps`; wait on conditions, never wall-clock time".
- Code that deliberately uses wall-clock time (`Time.get_ticks_msec()`, timers with `ignore_time_scale`, such as the "real time" self-hitstop) no longer lines up with game time under the flag. All suites passed anyway, but tests of wall-clock behavior should say so explicitly and live in small dedicated suites.

### 3.7 [MED] Leaks at exit: what teardown can and can't fix (measured)

The hypothesis to test was that "dynamic scenes freed right before `quit()` don't get frames to finish, so the harness should flush frames before quitting." The experiment in §2.12 **disproves it as the main cause**. Flushing 3 frames after `queue_free()` didn't reduce the leaks (338 → 359 objects, 80 → 90 RIDs). Nodes that are *in the tree* at `quit()` are freed by `SceneTree` finalization anyway, and a `NavigationRegion3D`'s server RIDs are released when the node is freed. What leaks is **orphans**: nodes created but never added to the tree, or removed without being freed. Nothing ever frees those. Freeing the orphans took the probe to 0/0.

Leak counts across the 45 suites (with `--fixed-fps`):
- 12 are clean.
- 5 leak 6–36 objects (test-created orphans).
- 28 leak 236–2,870. That's every suite that loads a level, which points to the `WaveObjective` bug (§2.12) rather than to test code.

So the harness teardown should do three things. Only the first two are "cleanup"; the third is what makes leaks useful:
1. **Free what the test created.** `autofree(node)` registers any node or scene the test instantiates. On teardown, in-tree nodes get `queue_free()` and orphans get `free()`.
2. **Flush frames** (`await process_frame` twice) so `queue_free` and `call_deferred` work settles before `quit()`. This is cheap and correct, just not the leak fix.
3. **Detect leaks instead of hiding them.** Record `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` in setup and compare after teardown. If it grew, call `Node.print_orphan_nodes()` and fail with "N orphan nodes leaked". That check would have caught §2.12 on day one. Start it as a warning while the existing leaks are fixed, then make it a failure.

### 3.8 In-house test harness (spec)

`test/lib/test_suite.gd`, one base class that every suite extends. Every suite is a `.tscn` whose root script extends it:

```gdscript
class_name TestSuite  # not usable while test/ is .gdignore'd — see note below
extends Node

## Override: return the ordered list of test methods (Callables) to run.
func get_tests() -> Array[Callable]: return []
## Override hooks.
func before_each() -> void: pass
func after_each() -> void: pass

## Soft assertion: records failure with message + caller line, continues the test.
func check(condition: bool, message: String) -> bool
## Equality helpers that print both sides (never compare to literals from scenes; see §3.5 rule).
func check_eq(actual: Variant, expected: Variant, message: String) -> bool
func check_approx(actual: float, expected: float, message: String) -> bool
## Waits up to max_physics_frames for predicate; records a failure with message on timeout.
func wait_until(predicate: Callable, max_physics_frames: int, message: String) -> bool
func wait_physics_frames(n: int) -> void
func wait_signal(sig: Signal, max_physics_frames: int, message: String) -> bool
## Registers a node for teardown (in-tree: queue_free; orphan: free). Returns it for chaining.
func autofree(node: Node) -> Node
## Instantiates a scene, adds it under the suite, registers it for teardown.
func spawn(scene: PackedScene, parent: Node = self) -> Node
## Loads the shared fixture arena (test/fixtures/arena.tscn) — see §3.4.6.
func load_arena() -> Node3D
## Input by action name only (InputEventAction), per AGENTS.md.
func press_action(action: StringName) -> void
```

Runner contract, implemented once in the base class's `_ready()`:
- Run each test in order, with `before_each`/`after_each`, autofree teardown and a frame flush after each test. One test's failure never stops the next.
- Print one line per test (`PASS name (Xms)` / `FAIL name: msg @ line`) and a summary.
- Run the orphan-node check (§3.7).
- Call `get_tree().quit(1 if failures > 0 else 0)` exactly once.
- The existing `run_tests.py` watchdog stays the outer guard, and it also fails on `SCRIPT ERROR` in the output (§3.4.1).

Notes:
- `test/` is `.gdignore`d, so `class_name` doesn't register there (§3.4.8). Suites should `extends "res://test/lib/test_suite.gd"`. Alternatively, move the harness to a non-ignored `res://testlib/` so `class_name TestSuite` works and agents get autocompletion. Either way, pick one and write it in AGENTS.md.
- Keep it under about 200 lines. The value for agents is that the whole API fits in one screen, and a template suite (`test/test_template.gd`) shows the idioms.

### 3.9 [HIGH] Frame-rate independence and mobile performance (added in revision 3)

**Does `--fixed-fps 60` hide frame-rate bugs?** Yes, if it's the only rate ever tested. It pins the *render* frame to 1/60 s, so the suite always sees exactly one physics tick per render frame. Physics code itself is not the main risk: Godot runs `_physics_process` at a fixed tick rate (60 Hz, the default) whatever the render rate, and on a slow device it runs several ticks per render frame to catch up. It starts to slow down game time only past `max_physics_steps_per_frame` (8). The risk is **gameplay timing driven from render frames**:

- **Animation-driven hit windows.** All three gameplay `AnimationTree`s (`player.tscn`, `animated_enemy.tscn`, `animated_enemy_brute.tscn`) use the default `callback_mode_process` = *Idle*. So `WeaponSlot:enabled` (the hitbox window) switches on render frames, not physics ticks. Measured windows: `Melee_2H_Attack_Chop` is enabled for only **0.030 s**. That's less than two physics ticks at 60 fps and can fall entirely inside one render frame at 30 fps, so the hitbox never becomes active during a physics step and the attack can't hit. The other windows are 0.20–0.80 s.
- **Timers and tweens that gate damage.** `SceneTreeTimer`s (for example `GroundDamageArea.active_duration = 0.2`) and idle tweens tick per render frame, so on a slow device their granularity is coarse compared with the physics steps that detect overlaps.
- **`_process` gameplay code:** `AttributeComponent` (timed modifiers, DoT ticks), `camera_rig_3d.gd`, `mannequin_animation_tree.gd`, `slash_vfx.gd`, `status_burning.gd`.
- **Tick-rate dependence** (a different axis): `core_movement()` decelerates with `move_toward(velocity, 0, speed)`, which has no `delta`, so it's per *tick*. That is harmless at any render rate, but changes behavior if `physics_ticks_per_second` is ever lowered to save battery on phones.

**Measured.** The whole suite was run with `--fixed-fps` set to 144, 30, 20 and 12 (`.scratch/fps/matrix.py`). Physics stays at 60 Hz, so this emulates a device rendering at that rate:

| Render rate | Result | Failing suites |
|---|---|---|
| 144 | 45/45 | none |
| 60 | 45/45 | none |
| 30 | **41/45** | `test_attack_aiming` (aimed attack never hits), `test_ground_aoe_jump` (AoE deals no friendly-fire damage), `test_firebomber_enemy` (target position), `test_akira_boss` (trap area growth) |
| 20 | **39/45** | `test_attack_aiming`, `test_attack_cycle` (first attack deals no damage), `test_combo_and_dash_cancel` (damage mismatch), `test_self_hitstop` (never reaches hitstop), `test_firebomber_enemy`, `test_ground_aoe_jump` |
| 12 | **41/45** | `test_attack_aiming`, `test_combo_and_dash_cancel` (attack 3 deals 0), `test_damage_flash_and_shake` (knockback velocity zero), `test_ground_aoe_jump` (standing player takes no AoE damage) |

Not every failure is a game bug. Some tests sample a position or size at a moment that depends on frame length (`test_firebomber_enemy`'s target `y`, `test_akira_boss`'s trap-area comparison). But the dominant symptom is **"a hit that should land doesn't"**, across player melee, combos and AoE. That matches the idle-driven hit-window mechanism above and is exactly what a mid-range phone at 20–30 fps would show players. **Each failure needs triage** into "game bug" vs. "test assumes 60 fps", and that triage is the first task of this workstream.

**Recommendations:**
1. **Make gameplay timing physics-driven.** Set `callback_mode_process` to *Physics* on gameplay `AnimationTree`s, or at least guarantee that an enabled hitbox gets at least one physics query: `WeaponSlot` latches `enabled` until the next physics tick, or calls `ShapeCast`/`PhysicsDirectSpaceState3D.intersect_shape` once when enabled. Use physics-processed timers (`create_timer(t, true, true)`) for damage windows. Purely visual animation can stay on Idle.
2. **Test in a frame-rate matrix.** Keep 60 as the default gate and add 20 and 30 (and 144 for high-refresh screens) as a CI job. It costs about 35 s per rate. Suites that genuinely only work at one rate must say so in a comment.
3. **Write explicit invariance tests with relative assertions.** For dash distance, jump airtime and apex, projectile travel per second of game time, a hit landing during each attack, total DoT over its duration, and knockback displacement: run the same scenario and assert that results agree across rates within a tolerance (for example 5%). Compare the rates with each other, never with literals, per §3.5. The harness can re-launch a suite per rate: `run_tests.py --fps 20,60,144`, with the suite reading `Engine.get_frames_per_second()`-independent game time from accumulated `delta`.
4. **Tick-rate axis.** Let the harness set `Engine.physics_ticks_per_second` from a user arg (`--physics-tps=30`) so tick-rate dependence (such as `core_movement`'s deceleration) is testable before anyone lowers it for mobile.

**Performance tests: not yet as pass/fail gates.** Wall-clock timings on this very fast dev machine don't predict a mid-range phone, and timing thresholds are flaky across machines. Useful now:
- **Decide the renderer for the phone target now.** The project uses Forward+ (`project.godot`), and every level is required to bake a **VoxelGI**, which is supported only by the Forward+ renderer, not by the Mobile or Compatibility renderers that mid-range phones realistically need. Continuing to build 13+ levels around VoxelGI builds up content debt. Options: set `rendering/renderer/rendering_method.mobile` and plan a LightmapGI (Mobile-supported) or unlit/ambient fallback, and add an Android export early.
- **Count-based budgets that don't depend on the machine**, checked in a capture run with a renderer: nodes, physics bodies, active particles and lights per level, plus draw calls and primitives via `Performance` monitors. Fail when a level exceeds its budget. These catch "an agent added 400 lights" regardless of CPU.
- **A benchmark scenario** (worst-case wave: max enemies, projectiles and AoEs) that logs frame time and physics time per commit as a trend, not a gate.
- **Real-device profiling** on a target phone with Godot's remote debugger and profiler at each milestone. That's the only source of truth for the phone budget.

**Proposed AGENTS.md test rule (replacing the current examples):**
> Any numeric literal in an assertion must be either (a) set by the test itself earlier in the same test, or (b) a mathematical identity (0, 1, `>0`, `is_zero_approx`). Values read from scenes/resources must be compared to *other live values*, never to literals. Inputs are referenced by action name only.

A cheap CI lint can enforce most of this: flag `is_equal_approx(<expr>, <literal>)` and `[!=]= <float literal>` in `test/` where the literal isn't assigned earlier in the same function.

---

## 4. Tooling and OS agnosticism

### 4.1 [HIGH] Machine-specific state committed to the repo

- `project.godot:39` sets `movie_writer/movie_file="D:/docs/godot/godot-roguelite-starting-project/movies/test1.avi"`. The editor writes this setting; clear it, or set it to `res://movies/…` (the folder is git-ignored).
- `test/capture_firebomber.gd:4` has `dest_path = "C:/Users/vibru/.gemini/antigravity/brain/<uuid>/orange_firebomber.png"`. This is another agent's private scratch path, committed.
- `test/record_fire_traps.gd:69` saves to `D:/docs/…/movies/…`.
- **Worktrees:** *(resolved by the owner in revision 2; only the untracked leftover directory `.worktrees/boss-arena-1/`, 75 MB, remains on disk.)* 5 worktrees lived in `C:/Users/vibru/.gemini/antigravity/worktrees/…`, outside the repo and against the AGENTS.md rule. One `/mnt/d/…` worktree is prunable (it was created from WSL, so Git on Windows can't resolve it). The 7 in `.worktrees/` take up **462 MB**. Several branches look merged or stale (`gemini-refactor`, `fix_duplicate_uid`, `implement_attribute_component`, …). Run `git worktree prune` and delete merged branches after confirming they're merged. The WSL/Windows path mix is a reason to require that worktrees are always created from the same shell.

### 4.2 [MED] Four separate Godot launchers

`run_tests.py`, `run_scratch.py`, `capture.py` and `tools/levels/build_level.py` each resolve the binary and implement their own watchdog:

- Only `build_level.py` unwraps a Windows `.cmd`/`.bat` shim (`engine_binary()`), so the others orphan the engine on timeout. That's the same failure mode AGENTS.md §7 warns about for `shell=True`, and it's why `run_tests.py` needed `reap_stale_headless_godot()`.
- Only `build_level.py` fails on `SCRIPT ERROR` in the output (§3.4.1).
- None honor an environment override such as `GODOT_BIN`. That's the portable way to pin a version per machine or CI.
- `run_tests.py` doesn't capture or flush output. When redirected to a file (as agents and CI do), its `[OK]`/`[FAIL]` lines appear only at exit, after all engine output. Use `print(..., flush=True)` or `python -u`.

**Recommendation:** create `tools/godot_env.py`, one module that the four scripts import. It should provide:

- `resolve_godot()`: `$GODOT_BIN`, then `shutil.which`, then shim unwrapping, then a version check against `4.7`.
- `run_godot(args, timeout, fail_on_script_error=True)`: `Popen` with process-group kill (`start_new_session=True` on POSIX, `CREATE_NEW_PROCESS_GROUP` plus `taskkill /T` on Windows) so kills reach the engine without the PowerShell reaper.
- Shared error-line detection.

### 4.3 [LOW] Other tooling notes

- `run_scratch.py` always passes `--quit-after 60`. That counts main-loop iterations, so a scratch script that `await`s a few frames of physics can be cut short silently. Make it a flag with a generous default, or drop it and rely on the watchdog.
- `run_scratch.py` checks `"extends SceneTree" in content`, which also matches a comment. Check the first non-comment `extends` line instead.
- Tests run serially. The big win is `--fixed-fps` (163 s → 35 s, §3.6). After that, time is dominated by about 0.7 s of engine startup per suite, and the suites are independent processes, so `run_tests.py -j N` with `concurrent.futures` is the next multiplier.
- `test/test_capture_system.py` isn't run by anything and needs a GPU. Document it as manual, or run it via `pytest -m gpu`.
- There's no CI. A GitHub Actions job on `ubuntu-latest` with a pinned Godot 4.7 headless build, running `python tools/godot_env.py --import` and then `python run_tests.py`, is the strongest guard against multi-agent drift. It also proves the environment is OS-agnostic, since today everything is exercised on one Windows box.
- CAPTURE.md's "D3D12" wording: `project.godot` sets `rendering_device/driver.windows="d3d12"` only for Windows, which is fine, but docs should say "a GPU display server (D3D12 on Windows, Vulkan elsewhere)".
- A headless editor import (`godot --headless --editor --quit`) is needed after adding a `class_name` (TODO #12, CAPTURE.md). Make it a runner subcommand (`python run_tests.py --reimport`) instead of tribal knowledge.

### 4.4 [MED] UID integrity (added in revision 2)

Godot 4 references resources as `[ext_resource … uid="uid://…" path="res://…"]`. The UID wins when it resolves; when it doesn't, the engine falls back to `path` **without printing anything in headless runs**. That's why none of the following showed up in the test log. Audit of all tracked `.tscn`, `.tres`, `.uid` and `.import` files:

| Check | Result |
|---|---|
| Two files owning the same UID (collision) | **0** today. The recently deleted `fix_duplicate_uid` branch suggests it has happened before. |
| `ext_resource` UID that nothing owns (stale reference) | **0 (corrected in Phase A).** Revision 2 reported 3 stale `hurtbox.gd` references. That was wrong: Godot decodes the invented `uid://d7hurtbox41zq` to the *same numeric ID* as the canonical `uid://c2y6regew58y`, so the references always resolved. The 3 binary `.res` hits were a scanner limitation. |
| Hand-written UIDs | **8 found, all fixed in Phase A**: `d7hurtbox41zq` (`hurtbox.gd.uid`, `enemy_base.tscn`) plus the scene headers of `objective_trail_3d`, `lobbed_spawn_projectile`, `map_capturer`, `test_spikes_hazard`, `test_fire_trap`, `test_ground_aoe_jump` and `record_fire_traps`. Godot accepts them because its decoder also takes `z`/`9`, but they're non-canonical spellings: `ResourceUID.id_to_text(text_to_id(t)) != t`. Each was rewritten to its canonical spelling, which is the same ID, so nothing changed behaviorally. |
| UID/path pair pointing at a *different* file | 0 |

So yes, **UID checks belong in the lint**, as three rules:
1. **No duplicate owners** across `.uid` sidecars, `.tscn`/`.tres` headers and `.import` files.
2. **Every `ext_resource` UID resolves to the file at its `path`.** Do this in a small headless GDScript step using `ResourceLoader.get_resource_uid(path)` and `ResourceUID.id_to_text()`, which handles binary `.res` correctly. The Python side can do the cheap text checks.
3. **UID text is canonical:** `ResourceUID.id_to_text(ResourceUID.text_to_id(t)) == t`. A regex alone isn't enough; `c8recf1retraps` passes `[a-y0-8]` but was still invented. This catches invented UIDs the moment an agent writes one.

AGENTS.md should also state the rule these checks enforce: **never hand-write or copy a `uid=` value.** When authoring `.tscn`/`.tres` text, either omit `uid=` on `ext_resource` lines (Godot accepts path-only references) or run `python run_tests.py --reimport` so the editor assigns and rewrites UIDs. When duplicating a scene file, delete the header `uid=` so the copy gets a fresh one, because a copied header UID is exactly how collisions happen.

---

## 5. Recommendations for a multi-agent codebase

The main risk is not any single bug. Agents with different styles each add a locally reasonable pattern (aliases "to be safe", fallbacks "just in case", tests that snapshot what they just built), and nothing pushes back. The fix is to turn conventions into **checks** and keep **one short canonical rulebook**.

### 5.1 Restructure the docs: always-loaded rules vs. on-demand skills

**Should docs become skills? Mostly yes, for procedures. Not for rules.**

How skills save context: in Claude Code, a skill in `.claude/skills/<name>/SKILL.md` costs only its `name` + `description` (one or two lines) in every session. The body, and any reference files next to it, are read only when the agent decides the task matches. Today AGENTS.md (273 lines) is loaded into every task, including its animation-extraction recipe, level pipeline and capture tips, even for a one-line UI fix. The deeper docs (CAPTURE.md 221 lines, tools/levels/README.md 345 lines) aren't loaded automatically; an agent finds them only if AGENTS.md mentions them and it chooses to read them.

The catch: a skill is loaded only if the agent **recognizes it needs it**. A rule the agent doesn't know it's breaking won't trigger anything. "Never hand-write a UID" must be in front of the agent when it writes a `.tscn` for an unrelated reason, and "never run bare `godot`" must be there before its first engine call. So split by *kind* of content:

| Content | Where | Why |
|---|---|---|
| Rules that apply to any task: typing, no compat shims, no hardcoded loads, always use the runners, never bare `godot`, test rules, UID rule, where scratch files go, git policy | **AGENTS.md** (target ≤ 120 lines, MUST/NEVER statements) | The agent must know these before it knows what's relevant. |
| One-paragraph architecture map (Body/Mind FSMs, components, damage pipeline, registries, autoloads), with links | **AGENTS.md** | Needed to make *any* change correctly. |
| Adding a combat animation (extraction recipe, 3 mandatory tracks, AnimationTree wiring) | skill `add-combat-animation` | A procedure, rarely needed. |
| Building or editing a level (template, GridMap metrics, `build_level.py`, VoxelGI/navmesh, rotation test) | skill `build-level`, with `tools/levels/README.md` as its reference file | A long procedure; already a good doc. |
| Capturing screenshots or video | skill `capture-media` (CAPTURE.md content) | A procedure. |
| Writing or migrating a test (harness API, rules, arena fixture, template suite) | skill `write-test` | Loaded whenever a test is touched. Keep the three hard test rules in AGENTS.md too. |
| *Diagnosing* a suite that already **timed out** (the runner returned `[TIMEOUT]`): watchdog-kill artifacts, engine timestamps, leaks | skill `debug-test-hang` (today's AGENTS §3 war stories) | Only reachable because the runner turned the hang into a result the agent can read. **Hang prevention is not in this skill:** "never launch Godot except through the runners" is the first rule in AGENTS.md (see §5.2 item 6 for enforcement that doesn't depend on reading it). |
| Adding an enemy / item / passive (resources to create, registries to update) | skills, once the registries are unified (§2.5) | Checklists are where agents most often miss a step. |

Caveats:
- **Skills are a Claude Code mechanism.** The repo history shows other agents (Gemini/Antigravity) working here too, and they may not auto-discover `.claude/skills/`. The skill files are still plain Markdown, so add a short index to AGENTS.md: "Before adding an animation, read `.claude/skills/add-combat-animation/SKILL.md`", and so on. Any agent gets on-demand loading by following the pointer, and Claude Code gets it automatically.
- **Keep one source of truth.** Move content into the skill and delete it from AGENTS.md/README. Don't copy it. The drift between AGENTS.md §8 and CAPTURE.md (§1.2) is what copying produces.
- **Descriptions drive triggering.** Write them as "Use when …" with the concrete nouns agents will see (`.res`, `AnimationTree`, `GridMap`, `VoxelGI`, `movies/`).
- Human-facing docs stay as docs: README.md (setup, commands), TODO.md (open items only), and optionally `docs/ARCHITECTURE.md` if the AGENTS.md map outgrows a paragraph.
- Add a `CLAUDE.md` / `GEMINI.md` that only imports or points to AGENTS.md, so every agent reads the same rules.

### 5.2 Add automated guardrails (cheap, high value)

1. **Decision (owner): no third-party linters.** The in-house lint below replaces `gdtoolkit`. It can include a few structural checks gdlint would have covered: max function length (for example 150 lines, which catches a 3,064-line `_ready()`), `const` and `@export` declared after the first `func`, and missing `##` docstrings on exports.
2. **`tools/lint_project.py`** (a small Python script plus one headless GDScript step for UID resolution) run by `run_tests.py` before the suites. It fails on:
   - UID collisions, stale `ext_resource` UIDs, and non-generatable (hand-written) UIDs (§4.4)
   - `load("res://` / `preload(` in production dirs (allowlist shaders)
   - absolute paths (`[A-Z]:/`, `/mnt/`, `/home/`, `.gemini`) in `.gd`, `.tscn`, `.godot`, `.py` and `.md`
   - `KEY_[A-Z]` in `test/`
   - float-literal assertions in `test/` (heuristic from §3.5)
   - the words `alias`, `legacy` or `backward` in production docstrings
   - Markdown references to missing files (the check this review ran found 18)
   - non-`test_*.tscn` files in `test/`
3. **Runner fails on engine `SCRIPT ERROR`s** (§3.4.1).
4. **CI** on Linux (§4.3).
5. **Pre-commit hook** running `tools/lint_project.py`.
6. **Hang prevention that doesn't rely on the agent reading anything.** An agent that runs `godot` directly bypasses every Python guardrail, and a stuck agent can't go read a skill. Layers, strongest first:
   - **Block direct engine calls in the agent harness.** In Claude Code, a permission deny rule or a `PreToolUse` hook rejects shell commands that launch the Godot executable directly, with a message pointing at the runners. Other harnesses need their own equivalent (command deny lists, per-command timeouts). Configure each one used here.
   - **Engine-side self-kill for headless runs (to prototype).** A tiny autoload that, only when running headless outside the editor, starts a thread that kills the process after a hard limit. That would make even a bare `godot --headless scene.tscn` return eventually. It can't cover failures before autoloads load (a `-s` script that doesn't extend `SceneTree`, a broken project file), so it complements the runners rather than replacing them. Verify it on `-s` runs before relying on it.
   - **Regression-test the runners themselves.** A fixture scene that never quits must make `run_tests.py`, `run_scratch.py` and `capture.py` return within their timeout and leave no engine process behind. Phase A shipped a runner that hung on exactly this case (fixed via `godot_env.py`), so it needs a test, run in CI.

### 5.3 Architectural conventions to write down (and follow)

- **Reference nodes by typed exports, never by name strings.** States reference other states through `@export var x: CharacterState`.
- **Required exports are validated in `_ready()`** with `push_error`. There's no silent `get_node_or_null` fallback and no hardcoded `load()` fallback.
- **Data owners.** Each datum has exactly one owner (see the table in §2.5). Balance lives in `.tres` resources or exported properties, never in `const` inside logic.
- **Controllers vs. body.** Only `PlayerInputComponent` / `AIStateMachine` know about input or AI. Body states read only `Character`. A formal `CharacterController` base with `command_*`/`order_*` would remove the duplicated method pairs in `PlayerInputComponent` and `AIStateMachine`.
- **Shared primitives where behavior is truly shared** (§2.9): `BallisticProjectile`, `AIAttackBase`, `DamageType`, a `Character.can_accept_order()` veto. Before extracting a base, diff the *behavior*, not the line count. Similar-looking per-context logic (cooldowns) is often correct as is.
- **Never hand-write UIDs** (§4.4). **Never pre-instantiate nodes you might not add to the tree** without owning their `free()` (§2.12).
- **Autoloads are assumed present.** Don't null-check them.
- **No production API for tests.** If tests need a hook, make it a documented public method.

### 5.4 Scratch verification vs. the permanent suite, and agent roles (added in revision 3)

**How the bad tests got in.** Nothing in the repo defines what a permanent test is for. AGENTS.md talks about tests at length, so an agent asked to "make the enemy orange" reasonably concludes that verifying work means adding a test, and `test/` is the only obvious place to put one. The recording scenes (`record_*`, `capture_firebomber`) landed in `test/` the same way. Fixing this needs a rule that makes the distinction explicit, a scratch path that is easier than the suite, and enforcement that doesn't depend on the agent remembering the rule.

**1. The rule (AGENTS.md, a few lines):**
> **Verifying your change ≠ adding a regression test.** By default, verify with a throwaway script or scene in `.scratch/` (git-ignored), run via `run_scratch.py` or `capture.py`, and delete or leave it there. Add or modify files in `test/` **only** when the task explicitly asks for tests, or when you are fixing a bug or adding a mechanic whose *behavior* can regress. A permanent test must pass the admission check: *(1) it asserts behavior a player or designer would call a bug if it broke; (2) it still passes after a designer retunes any exported value, recolors or remodels anything, or rebinds any key; (3) it uses only the public API and the test harness.* Visual/cosmetic changes (colors, meshes, VFX, UI layout) are verified with `capture.py`, never with suite tests.

**2. Make scratch the easy path.** The harness (§3.8) should work in `.scratch/` too: a scratch check can `extends` the same `TestSuite` and gets `check()`, `wait_until()` and cleanup, but `run_tests.py` only collects `test/test_*.tscn`. Extend `run_scratch.py` to accept a `.tscn` as well as `-s` scripts, so in-scene verification doesn't push agents toward `test/`. `CAPTURE.md`/the `capture-media` skill is the documented way to verify visuals.

**3. Enforce it mechanically.** Pick layers according to which agents run here:
- **Lint** (§5.2): `test/` may contain only `test_*.tscn`/`.gd`, `lib/` and `fixtures/`. Every suite extends the harness, and the literal-assertion and `KEY_*` rules apply. That alone would have rejected the albedo test.
- **Path permissions per role.** In Claude Code, a session or subagent can deny `Edit(test/**)`/`Write(test/**)` through permission rules in its settings, or through a `PreToolUse` hook that blocks writes under `test/` unless the task is a test task. Other agent tools need their own equivalent, so the backstop is at the git level:
- **CI check on test changes:** a job that fails, or requires owner approval, when a change touches `test/` without an explicit marker (for example a `tests:` commit prefix, or a CODEOWNERS rule on `test/` if the work goes through PRs).

**4. Split roles: yes, as "spec author vs. implementer", with caveats.**

| Role | Who | May change | Output |
|---|---|---|---|
| Spec/test author | Stronger model (or you) | `test/`, harness, fixtures, public interfaces/stubs | Behavioral tests that fail for the right reason; spot-checks that they catch a deliberate break |
| Implementer | Cheaper/faster model | Production code only; `.scratch/` freely | Code that passes the suite; **must stop and report** if it believes a test is wrong, never edit it |
| Reviewer | Stronger model | Nothing (read-only) | Review of the implementer's diff for design and practices: aliases, fallbacks, hardcoded values, duplication |

Why it helps: implementers under pressure to go green are known to weaken or special-case tests (assert what the code happens to do, loosen tolerances, hardcode expected values). Taking away write access to `test/` removes that option. It also puts test design, the hardest part to get right (§3.1–3.3), with the most capable model.

Caveats:
- **Tests constrain behavior, not design.** Every design problem in §2 would pass a perfect suite. The reviewer role, plus lint, catches those. Tests-only gating gives a green but messy codebase.
- **Test-first needs an interface.** The spec author must define the public API the tests call (method names, signals, exports), or the implementer is forced into the test author's guesses. Over-specified tests (private methods, node names) recreate §3.4.4.
- **Escalation path.** When the implementer disagrees with a test, the right flow is: report, the test author fixes or confirms, repeat. Budget for that round trip.
- It pays off most for new mechanics and bug fixes. For pure content work (new level, new item `.tres`), a single agent plus lint plus the existing suite is enough.

**5. Does CI help?** Yes, as the *impartial gate*, but it isn't the separation mechanism by itself:
- It runs the full suite, the frame-rate matrix (§3.9) and lint on every push, in a clean Linux environment. That proves OS-agnosticism and catches "works on the dev box".
- The implementer can't declare done while CI is red, and it can't quietly change what CI runs if `test/`, `run_tests.py` and the CI config are write-protected for its role.
- What CI can't do is stop an agent from editing tests *locally* and pushing both. That's what the path permissions and the `test/` change check are for. So: CI gates the result, permissions separate the roles.

### 5.5 Suggested order of work

**The key point:** "fix the bad tests" and "move to the new harness" are **one step** (step 4), not two. Rewriting a suite onto the harness means rewriting each of its checks anyway, and that's when its hardcoded values get removed. Revision 1 had these as separate steps (first and last), which would have touched every assertion twice.

Steps 1–3 are **prerequisites** for that merged step, not alternatives to it. Two terms that are easy to mix up:
- **Runner** = `run_tests.py`, the Python script *outside* Godot that launches each suite with a watchdog and decides pass/fail from the result.
- **Harness** = `test/lib/test_suite.gd`, the GDScript base class *inside* each suite that provides `check()`, `wait_until()`, cleanup and the leak check.

The harness depends on the runner being trustworthy and fast, so the runner is fixed first.

**Phase A: foundation (prerequisites, in this order)**

1. **Harden the runner.** In `run_tests.py`:
   - add `--fixed-fps 60` (§3.6)
   - fail on `SCRIPT ERROR` / `Parse Error`
   - add `flush=True`
   - only collect `test_*.tscn`

   Also move the 4 recording scenes out of `test/` and fix the `level_rotation_nav` item-21 error. *Why first:* until the runner fails on script errors, a "pass" doesn't prove much, and the 4.7× speedup makes every later step cheaper.
2. **Fix the two production bugs the harness will expose:** the `WaveObjective` orphan leak (§2.12) and the 3 stale `hurtbox.gd` UIDs (§4.4). *Why before the harness:* the harness's leak check would otherwise fail every suite that loads a level.
3. **Build the harness and the arena fixture** (§3.8, §3.4.6), plus a `test/test_template.gd` example. Prove it by converting **one** small suite (for example `test_character_rotation`) as the reference migration.

**Phase B: the merged step, plus a parallel track**

4. **Migrate the suites to the harness, one suite per commit. This is where the bad tests get fixed.** Each migration:
   - switches to the harness API
   - removes that suite's literal, key and art assertions (§3.1–3.3)
   - replaces private calls with public APIs (§3.4.4)
   - moves mechanics tests to the arena

   `test_enemy_base.gd` gets split into feature suites during its migration. Rules per migration:
   - The suite must pass before and after.
   - Spot-check a couple of converted checks by breaking the code temporarily and confirming the test catches it.
   - Don't mix production refactors into migration commits.

   Suites not yet migrated keep working, because the runner contract doesn't change.

5. **Frame-rate workstream: a parallel track that can start as soon as step 1 is done** (it's HIGH severity and doesn't need the harness):
   - triage the 30/20/12 fps failures into game bugs vs. 60 fps test assumptions
   - make hit windows and damage timers physics-driven
   - add the frame-rate invariance tests (§3.9)
   - decide the renderer/GI strategy for mobile before building more VoxelGI-dependent levels

**Phase C: guardrails (after step 4, so they describe what actually exists)**

6. **Rewrite AGENTS.md and create the skills** (§1, §5.1), including the scratch-vs-suite rule and the role table (§5.4). Trim TODO.md and fix README.
7. **`tools/lint_project.py`**, including the UID checks (§5.2, §4.4). Adopt it with a baseline, fail on *new* violations, and burn the backlog down.
8. **Shared Godot launcher module, `GODOT_BIN`, and CI** (§4.2–4.3), including the frame-rate matrix job (§3.9) and the `test/` change check (§5.4).

**Phase D: production cleanup (now protected by trustworthy tests)**

9. **Remove the aliases and legacy paths** (§2.6) and the hardcoded fallbacks (§2.7). Fix the `AILeapingDodge` sentinel (§2.8). The migrated tests no longer depend on the aliases, so this is safe.
10. **Unify the level registry and the other duplicated owners** (§2.5).
11. **Structural refactors:**
    - string state names → exports (§2.2)
    - input bridge out of `StateMachine` (§2.3)
    - `BallisticProjectile`, `AIAttackBase`, and body-owned cooldown ticking (§2.9)
    - split `Character`/`AttributeComponent` (§2.1)

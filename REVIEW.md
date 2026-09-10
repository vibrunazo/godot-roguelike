# Adversarial Review: Gemini Refactor (Issue #2 — Unified Character & Dual State Machines)

Scope: `git diff master...gemini-refactor` (~2100 insertions, ~815 deletions, 72 files).
Method: static read-only audit inside WSL. No game code, scenes, or scripts were modified.
Per the task guardrails, no Godot build/run/test commands were executed in this session,
so the "13/13 tests pass" claim in `gemini-refactor-walkthrough.md` is taken from
Gemini's pasted log, **not independently re-verified here**.

---

## 1. Executive Summary & Verdict: **Needs Polish** (not a redesign)

Gemini delivered the core of what was asked, and the architectural direction is sound:

- ✅ `Player`/`Enemy`/`RangedEnemy` classes are gone; both player and enemies instantiate
  `Character` (`Character/character.gd`) and differ by components + `player`/`enemy` groups.
- ✅ Controls are decoupled: `PlayerInputComponent` for input, `AIStateMachine`
  (extends `StateMachine`) for the mind, body `StateMachine` for physics/animation.
- ✅ Former body/AI hybrids (`EnemyPursue`, `EnemyMeander`, `EnemyWait`) are replaced by
  mind states (`AIPursue`, `AIMeander`, `AIWait`, plus new `AIAttack`) that order the body
  via `command_move` / `command_stop` / `order_attack`. Stun no longer breaks the mind
  (covered by the new Part 5 test).
- ✅ Ranged cadence regression was caught and reworked (mind-level 50/50 `AIWait` 2.0 s /
  `AIMeander` cycle), and corpse lock-down after defeat is thorough at the `Character`
  level.

But there is one genuine gameplay regression (enemies now all spawn stacked at one point
instead of scattered), several dead-end/orphan nodes in the AI graphs, a wrong static type
on the most important export in the refactor, stringly-typed cross-machine coupling with
silent failure, and a test that exercises a method production code never calls. None of
these requires throwing the architecture away. All are fixable in place — hence
**Needs Polish**, close to Pass once the punch list ( §5 ) is done.

---

## 2. Intent & Scope Gaps (prompt vs. reality)

| # | Prompt requirement | Reality |
|---|---|---|
| 1 | One `Character` class; player/enemy differ only by components + group | Delivered. `Player/player.tscn` and `Enemy/enemy.tscn` both run `character.gd`, groups `player` / `enemy` verified by tests. |
| 2 | Controls as components; input listens, AI is a state machine reusing/extending `StateMachine` | Delivered. `AIStateMachine extends StateMachine`; `PlayerInputComponent` writes intents. |
| 3 | Old pursue-style AI becomes mind states, not body states | Delivered. `AIPursue`/`AIMeander`/`AIWait`/`AIAttack` under `AIStateMachine`; body has neutral `EnemyMove`. |
| 4 | Two machines run simultaneously; mind orders body; stun hits body only | Delivered and tested (Part 5: `order_attack` blocked during `EnemyStun`, body recovers to `EnemyMove`). |
| 5 | Groups used for searching + AI targeting | Delivered (`get_nearest_target`, `AIStateMachine.target_group`, `get_target`). Damage itself is still unfiltered (melee can hit any `HealthComponent`, including allies) — same as before, so arguably out of scope, but the prompt's "which team to attack" is only half-wired: targeting yes, damage no. |
| 6 | No placeholder logic | Mostly true, but: base `enemy.tscn`'s `AIWait` has **no `next_state`** (dead end, §3.2), melee's `AIWait` is unreachable (orphan, §3.3), and `AIAttack.end_attack()` is public API nothing calls (§3.7). |
| 7 | No behavior regressions | One real regression: random-spread enemy spawning was deleted and replaced with stacking at `(0,1,0)` (§3.1). Ranged cadence was broken mid-refactor and then restored per the walkthrough — credible, but the test proves it via a dead method (§3.7). |

Out-of-scope carryovers (correctly left alone, noted for completeness): `AttackComponent`
still uses `has_node("HealthComponent")` string lookups (TODO #12), `WaveObjective` still
hardcodes scene preloads (TODO #8), projectiles are still parented to their shooter
(TODO #10 — `Components/projectile_spawner_component.gd:25` does
`character.add_child(projectile)`, same lifecycle trap the old `RangedEnemy` had).

---

## 3. Critical Bugs & Regressions (prioritized)

### P0 — Gameplay regression

**3.1 Enemies spawn stacked at one point; random-spread spawn was deleted.**
- Old `Enemy/enemy.gd` `_ready()` teleported each enemy to a random navmesh point
  (with capsule half-height lift). New `Character/character.gd` `_ready()` (lines 49–84)
  has no spawn placement at all.
- Compensation added in the wrong layer: `Levels/wave_objective.gd:16` sets
  `new_enemy.position = Vector3(0.0, 1.0, 0.0)` for every enemy, and
  `test/test_utils.gd` got the same workaround. Result: a wave spawns as a single
  overlapping stack at the origin until AI wanders them apart; also risks spawning
  inside geometry that the old random-point logic avoided.
- Fix: restore navmesh-spread placement (spawn points or random-point-on-ready in one
  place, e.g. the spawner), and remove the per-enemy hard-coded origin.

### P1 — Logic / wiring defects (all reachable in normal play or tests)

**3.2 Base `enemy.tscn` mind dead-ends in `AIWait`.**
- `Enemy/enemy.tscn:90-92`: `AIWait` sets only `ai_state_machine`, no `next_state`
  (and default `wait_duration`). `AIWait.end_wait()` (`StateMachine/AIStates/ai_wait.gd:31-39`)
  no-ops when `next_state == null`, so a base enemy idles in `EnemyMove` forever after ~2 s.
- Base scene isn't spawned by `WaveObjective` (only melee/ranged), and tests only assert
  initial states, so nothing catches it. Still: a base class scene that stalls its own
  mind is a trap for the next person who spawns it.

**3.3 Melee `AIWait` is orphaned.**
- `Enemy/melee_enemy.tscn:60-61`: `AIWait.next_state -> AIPursue` exists, but nothing
  transitions *into* melee `AIWait` (initial state is `AIPursue`; `AIPursue` has no
  `lost_target_state`; there is no `AIAttack` in melee). Harmless at runtime, but it is
  dead configuration that will confuse the next reader into thinking melee idles.

**3.4 `Character.ai_state_machine` is statically typed as the wrong class.**
- `Character/character.gd:29`: `@export var ai_state_machine: StateMachine`.
  `Character/character.gd:185` then calls `ai_state_machine.command_stop()` and
  `StateMachine/EnemyStates/enemy_defeat.gd:21` does the same — `command_stop()` only
  exists on `AIStateMachine`. It works at runtime (the assigned node *is* an
  `AIStateMachine`), but the declared type is a lie: static tooling can't verify it,
  and a future plain-`StateMachine` assignment would fail at runtime instead of at edit
  time. Type it `AIStateMachine`.

**3.5 Enemy-specific state names are hard-coded into the shared base class.**
- `Character/character.gd:68-71` falls back to
  `state_machine.get_node_or_null("EnemyStun")` / `"EnemyDefeat"`. `Character` is
  supposed to know nothing about enemy concretes; the player (which has neither node)
  silently gets `null` stun/defeat states. It happens to match old player behavior
  (player never stunned), but the next body state added for either side has to edit the
  base class. Wire these purely through scene exports; make the fallback at most a
  `printerr`, never a silent `null`.

**3.6 `order_attack` fails silently on name mismatch.**
- `StateMachine/ai_state_machine.gd:53-58` compares raw strings
  (`"EnemyStun"`, `"EnemyDefeat"`, `"EnemyFall"`, plus the requested attack name) and
  returns `false`. A renamed body state makes `AIAttack.enter()` immediately
  `_finish_attack()` every physics tick — rapid silent AI cycling with zero log output.
  At minimum `printerr`/`push_warning` on the reject path during development; better,
  replace string names with direct state references or an `can_be_interrupted`-style
  flag on body states.

**3.7 The "attack timing" test verifies a method the game never calls.**
- `AIAttack.end_attack()` (`StateMachine/AIStates/ai_attack.gd:38-39`) has zero
  production callers; real completion flows through the `physics_update()` poll
  (`state.name != attack_state_name`). But `test/test_character_and_ai.gd:427`
  (`test_part_7`) drives completion via `ai_attack.end_attack()`. So the headline
  "no machine-gun spam" assertion passes without exercising the real loop. Keep the
  unit check, but add a polling-path test: put the body in `EnemyAttack`, emit the
  animation finish (or force body back to `EnemyMove`), run AI `physics_update`, and
  assert the mind leaves `AIAttack` for `AIWait`/`AIMeander`.

**3.8 `AIAttack.enter()` emits `finished` synchronously from inside a transition.**
- `StateMachine/AIStates/ai_attack.gd:13-22`: when the body can't attack,
  `enter()` → `_finish_attack()` → `finished.emit()` while `StateMachine` is still
  inside `_transition_to_next_state` for the *first* transition (re-entrant
  `exit()`/`enter()` on a half-entered state). It resolves by accident today
  (`_attack_ordered` is cleared before emitting), but `StateMachine` has no
  re-entrancy guard, so any future line added between the flag-clear and the emit (or
  any new caller of `order_attack` from `enter()`) can corrupt `state`. Defer the
  fallback (`call_deferred` or a zero-timer) or make `StateMachine` queue
  transitions emitted during `enter()`.

### P2 — Robustness / edge cases

**3.9 Body ticks before mind every frame (1-frame command latency, order-dependent).**
- In `Enemy/enemy.tscn`, `StateMachine` precedes `AIStateMachine` in tree order, so the
  body consumes last tick's intents and the mind's orders land a frame late. Same for
  `PlayerInputComponent` → body (currently saved by child order in `Player/player.tscn`,
  but nothing documents that the order is load-bearing). Either reorder mind/input
  before body explicitly or note the contract; don't leave frame latency to file order.

**3.10 `EnemyMove` rotates the mesh twice per tick.**
- `StateMachine/character_state.gd:25` smooth-rotates toward the move direction inside
  `core_movement()`, then `StateMachine/EnemyStates/enemy_move.gd:23-24` snap-rotates
  toward `face_direction`. The snap wins, making the `decay` smoothing dead code for
  enemies (and a behavior change vs. old snap-only rotation). Pick one: keep smoothing
  for locomotion and use `face_direction` only when the body is idle, or document the
  override.
- Related naming trap: `AIStateMachine.command_move(direction, face_dir)` is always
  called with a world *position* as `face_dir` (`ai_meander.gd:66`,
  `ai_pursue.gd:39`), while `Character.face_direction`'s docstring
  (`character.gd:45`) says "direction". Someone passing an actual direction vector
  will face the wrong way. Rename to `face_target`/`face_position` or accept both
  explicitly.

**3.11 Player side has no defeat lock (walkthrough overclaims).**
- The corpse-rotation/intent lock is enemy-only. `PlayerInputComponent._physics_process()`
  (`Components/player_input_component.gd:22-26`) has no `is_alive()` guard, so it keeps
  overwriting the zeroed intents after death until the deferred scene reload. The
  "post-death movement/rotation completely locked" claim (§3 of the walkthrough) holds
  for enemies, not the player. One-line guard (or disabling the component on defeat,
  mirroring the AI shutdown) closes it.

**3.12 `PlayerAttack.enter()` connects `animation_finished` without an `is_connected` guard.**
- `StateMachine/PlayerStates/player_attack.gd:53` vs. the guarded pattern used in
  `enemy_attack.gd:35` / `enemy_stun.gd:24`. Safe today (every `enter` is preceded by
  `exit`, which disconnects at line 81), but it is the only attack state that relies on
  that invariant implicitly. Add the guard for symmetry.

**3.13 Scene `ext_resource`s dropped their UIDs.**
- `Player/player.tscn`, `Enemy/enemy.tscn`, `Enemy/melee_enemy.tscn`,
  `Enemy/ranged_enemy.tscn` reference the new scripts by `path` only
  (e.g. `path="res://Character/character.gd"` with no `uid`), while every other
  reference in the same files carries a `uid`. The matching `.uid` files exist on
  disk, so this is just editor hygiene — but TODO #11 was literally "standardize
  UIDs", and a re-save will churn all four scenes. Re-save in-editor or backfill the
  UIDs now.

**3.14 Inconsistent AI shutdown between the two defeat paths.**
- `Character._on_health_component_defeat()` (`character.gd:184-187`) disables both
  `set_physics_process(false)` and `set_process_unhandled_input(false)`;
  `EnemyDefeat.enter()` (`enemy_defeat.gd:20-22`) disables only physics. AI states
  don't handle input today, so this is cosmetic — but two defeat paths doing
  overlapping-but-different teardown is exactly how a future `handle_input` on an AI
  state becomes a corpse-input bug. Unify (one helper, called from one place).

---

## 4. Architectural Critique & Polish Suggestions

1. **Direction is right; layering is honest.** Unified `Character` + thin
   `CharacterState`/`PlayerState`/`EnemyState` + `AIState`/`AIStateMachine` + two tiny
   components (`PlayerInputComponent`, `ProjectileSpawnerComponent`) is an appropriate
   size for this codebase. No new autoloads, no manager-itis, no framework. Keep it.
2. **Mind/body split is clean where it matters.** The money property — damage/stun
   moves the body without disturbing the mind, and the mind can't yank the body out of
   `EnemyStun`/`EnemyFall`/`EnemyDefeat` — is enforced in exactly one place
   (`order_attack`), and Part 5 pins it. Good.
3. **But the seam is stringly-typed.** Mind→body calls go through node *names*
   (`order_attack("EnemyAttack")`, `finished.emit(next_state.name)`), and the base
   class knows `"EnemyStun"`/`"EnemyDefeat"` by literal. For 4 AI states and 5 body
   states this is tolerable; past ~10 states it becomes rename-roulette. Cheapest
   hardening without a data-driven rewrite: export typed state references
   (`@export var attack_state: EnemyState`) on the AI states the way `AIMeander`
   already does for `attack_state`/`wait_state`, and give body states an
   `interruptible: bool` instead of name-checks.
4. **`Character` is a little too helpful.** The `_ready()` fallback chain
   (`get_node_or_null("HealthComponent")`, `find_child("AnimationTree", …)` twice,
   mesh-mount guessing across two different rig layouts) means a mis-wired scene
   boots with a half-wired character instead of failing loud. Since all shipped scenes
   already set every export explicitly, demote the fallbacks to diagnostics: keep the
   lookup, add `push_warning` naming the scene + missing export when one fires.
5. **Defensive copies of the same teardown in three places** (`Character._on_defeat`,
   `EnemyDefeat.enter`, AI guards) suggest a missing method: `Character.on_defeat()`
   (zero intents/velocity, stop + disable AI, disable collision, emit) called once from
   the health signal, with `EnemyDefeat.enter()` handling only animation. Today the
   three copies agree; they won't after the next edit.
6. **`face_direction` semantics need settling** (position vs. direction, §3.10) before
   anyone builds strafing, backstabs, or directional shields on top of it.
7. **Code cleanliness is high overall.** New files are short, documented, consistently
   named (`ai_*`, `enemy_*`, `player_*`), squared-distance comparisons follow TODO #7,
   and the diff *removes* ~800 lines including two whole classes. The main readability
   debts are the ones above (string coupling, fallback magic, orphan AI nodes), not
   style.
8. **AGENTS.md compliance: essentially clean.**
   - *Strict typing* (`warnings/untyped_declaration=1`): every new
     variable/parameter/return I sampled carries a type. `_data := {}` in `enter()`
     overrides relies on inference, but that matches the pre-existing `State.enter()`
     convention rather than introducing a new violation. Two nits: `ai_state_machine`
     is typed as the *wrong* class (§3.4), and `Character.get_nearest_target()` /
     `AIStateMachine.get_target()` return nullable `Character` under a non-nullable
     annotation — legal in GDScript, but callers must (and do) null-check.
   - *Documentation integrity*: new classes/exports/functions are documented, with one
     exception — `StateMachine/PlayerStates/player_attack.gd:1` starts with
     `class_name PlayerAttack` and no `##` class docstring, unlike every other new or
     touched state file.
   - *State machine pattern*: transitions still go through
     `finished.emit(name, data)`; no new pattern invented. The re-entrancy hazard in
     §3.8 is a latent violation of the pattern's assumptions, not a deviation from it.
   - *No commit/push performed here*; tests were not executed per the WSL guardrail.

---

## 5. Actionable Implementation Punch List (paste straight back to Gemini)

Each item is scoped, file-pinned, and independently verifiable. Suggested order: P0 → P1 → P2.

- [ ] **P0-1 Restore scattered enemy spawning.** Reintroduce random-navmesh (or designer
  spawn-point) placement for wave enemies so they don't all start at `(0,1,0)`;
  delete the hard-coded origin in `Levels/wave_objective.gd:16` and the matching
  workaround in `test/test_utils.gd`. Verify: spawn a wave, assert pairwise distances
  are not all ~0 and all enemies are on the navmesh.
- [ ] **P1-1 Type the AI export correctly.** `Character/character.gd:29`:
  `@export var ai_state_machine: AIStateMachine` (not `StateMachine`). Verify: project
  loads, melee/ranged scenes assign without warnings, defeat path still disables AI.
- [ ] **P1-2 Remove enemy literals from the base class.** `Character/character.gd:68-71`:
  replace the `"EnemyStun"`/`"EnemyDefeat"` fallback lookup with pure export wiring
  (scene-assigned), plus a `push_warning` when either is missing on an enemy-group
  character. Verify: player boots with both `null` and no warning-spam; enemy boots
  with both set and no fallback taken.
- [ ] **P1-3 Fix the AI graph dead ends.** Either give base `Enemy/enemy.tscn`'s `AIWait`
  a real `next_state` (or document the base scene as abstract / remove it from spawn
  pools and tests that treat it as playable), and either wire melee's `AIWait` into the
  loop or delete the node from `Enemy/melee_enemy.tscn`. Verify: every shipped
  `AIStateMachine` can reach every one of its states in a dry-run walk.
- [ ] **P1-4 Make `order_attack` failures visible.** `StateMachine/ai_state_machine.gd:53-58`:
  add a `push_warning` (state names involved) on every `return false`, and file the
  follow-up to move from name comparison to typed references / `interruptible` flag.
  Verify: rename a body state in a scratch scene, observe a warning instead of silent
  AI spinning.
- [ ] **P1-5 Test the real attack-completion path.** Extend `test_part_7` (or add Part 9):
  drive `AIAttack` completion through `physics_update()` polling (body in `EnemyAttack`
  → body back to `EnemyMove` → assert mind is in `AIWait`/`AIMeander`), not just the
  direct `end_attack()` call. Keep the direct call as a unit check. Verify: the new
  assertions fail if the poll condition is inverted.
- [ ] **P1-6 Defer the can't-attack fallback out of `enter()`.**
  `StateMachine/AIStates/ai_attack.gd:19-22`: when `order_attack` returns false, do not
  `finished.emit` synchronously from `enter()` — defer it (or add a transition queue
  guard in `StateMachine/state_machine.gd`). Verify: force the stunned-during-`AIAttack`
  case, assert exactly one downstream transition and no double `exit()`.
- [ ] **P2-1 Pin the tick order contract.** Ensure mind/input nodes process before the
  body `StateMachine` (scene order + a comment, or explicit `process_priority`), and
  document that the order is load-bearing. Verify: log one frame of
  mind-write → body-read and confirm zero-frame staleness.
- [ ] **P2-2 Settle `face_direction` semantics.** Rename to `face_target` (world
  position) or split direction vs. position; update `Character/character.gd:45`,
  `AIStateMachine.command_move()`, `AIMeander`, `AIPursue`, `EnemyMove`. While there,
  remove the double rotation (`character_state.gd:25` + `enemy_move.gd:23-24`) — keep
  smoothing for locomotion, snap only when idle-facing. Verify: enemy facing a
  stationary target no longer jitters between two rotations.
- [ ] **P2-3 Lock the player corpse.** Guard `PlayerInputComponent._physics_process()`
  with `character.is_alive()` (or disable the component in
  `Character._on_health_component_defeat()`, mirroring the AI shutdown). Verify: kill
  the player with movement keys held; intents stay zero until reload.
- [ ] **P2-4 Unify defeat teardown.** Single `Character.on_defeat()` helper owned by the
  health signal; `EnemyDefeat.enter()` handles animation only (including the missing
  `set_process_unhandled_input(false)` parity). Verify: defeat twice in a row is
  idempotent; AI input+physics both off in both paths.
- [ ] **P2-5 Small hygiene sweep.** Add the missing `##` class docstring to
  `player_attack.gd:1`; add the `is_connected` guard to its line-53 connect;
  backfill `uid`s on the new `ext_resource` script references in all four
  player/enemy scenes; connect `AIWait.timer.timeout` with `CONNECT_ONE_SHOT` (or
  document why not). Verify: no UID churn on next editor save; no double-connect
  possible by construction.

---

## 6. Appendix & Additional Notes

- **What Gemini got notably right (keep):** deleting rather than aliasing
  (`Player`/`Enemy`/`RangedEnemy` fully removed, no compat shims — exactly what the
  plan promised); moving `dash_speed` onto `PlayerDash` (upgrades only touch
  `movement_speed`/`damage_stat`, confirmed in `upgrade_speed.tscn` /
  `upgrade_damage.tscn`, so nothing breaks); `ProjectileSpawnerComponent` replacing the
  `RangedEnemy` subclass with a single signal rewiring
  (`ranged_enemy.tscn:46`); squared-distance checks in the new AI states (TODO #7
  applied at the right moment); the walkthrough's honest before/after timing table.
- **Signal double-connection audit:** `Enemy/enemy.tscn:96-97` retains scene-level
  `defeat` + `health_changed` connections *and* `Character._ready()` connects the same
  pair in code — safe only because of the `is_connected` guards
  (`character.gd:74-77`). Fragile but correct; do not remove either side without
  removing the other. Player has code-only connections; no duplication there.
- **Pre-existing holes Gemini inherited (not his bugs, don't bill him):**
  `AttackComponent.reset_exceptions()` in attack `enter()` wipes the self-exception
  from `Character._ready()` (self-hit avoided only by hitbox placement, same as
  before); `HealthComponent` stuns on *any* `health_changed` including heals (no heal
  exists yet); `StateMachine._transition_to_next_state` `printerr`s on unknown targets
  but AI paths never hit it because `order_attack` pre-filters silently (§3.6).
- **Biggest forward-looking risk:** the string-coupled mind/body seam (§3.6 + §4.3).
  It is fine at the current state count, but the next feature that adds states
  (ranged strafe, elite variants, a player-side companion AI reusing `AIStateMachine`)
  should budget the typed-reference cleanup first — otherwise renames will produce
  silent behavior changes that tests only catch if they assert transitions (as Parts
  5/7 do) rather than wiring (as Part 4 does).
- **Review limits:** this audit is static. Gemini's pasted `python run_tests.py`
  transcript (13/13 OK) was not re-executed here per the read-only WSL instruction;
  the P1-5 test-gap finding (§3.7) stands regardless of the green suite, since the
  suite itself routes around the production code path.

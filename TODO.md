# Post-Course Refactoring & Scalability Backlog

This document tracks architectural improvements, optimizations, and technical debt to address after completing the course lessons. While following the course, we adhere closely to the instructor's implementation to stay aligned with the tutorial; this list outlines items to refactor toward a clean, production-ready codebase.

---

## 1. Projectile & Melee Weapon Collision & Performance (ShapeCast vs. Event-Driven Area3D) [RESOLVED]
- **Status**: Completed. Converted both melee weapons (Player, MeleeEnemy) and projectiles (EnemyProjectile) from polling-based `ShapeCast3D` to pure event-driven `Area3D` signals.
- **Problem**: 
  - `AttackComponent` previously relied on `attack_shapecast.force_shapecast_update()` and polled collisions every physics tick in `_physics_process()`.
  - Melee weapons and projectiles used `ShapeCast3D`, polling queries each frame in GDScript instead of letting Godot's C++ physics engine dispatch collision events.
- **Resolution**:
  - Replaced `ShapeCast3D` under `WeaponSlot` in `Player` and `MeleeEnemy` scenes with `HitboxArea` (`Area3D`), collision shapes, and visual meshes.
  - Refactored `WeaponSlot` to export `hitbox: Area3D`, dynamically toggling `hitbox.monitoring` and `hitbox.monitorable` when `enabled` changes.
  - Converted `EnemyProjectile` to extend `Area3D`, completely removing polling and physics sweeps from `_physics_process()`.
  - Refactored `AttackComponent` to listen to `Area3D` built-in `body_entered` and `area_entered` signals, completely eliminating `force_shapecast_update()` and per-tick GDScript collision polling.
  - Added `deal_damage_to()` and export properties `damage` and `knockback`, configured upon entering attack states.
  - All 12 automated test suites pass cleanly with exit code 0.

---

## 2. Character & State Machine Architecture (Decoupling AI from Body Action States) [RESOLVED]
- **Status**: Completed. Unified Player and Enemies into a single `Character` class, decoupled player inputs and AI decision-making into dedicated components, implemented dual state machines (Mind vs Body) on enemies, and standardized team targeting via `"player"` and `"enemy"` groups.
- **Problem**:
  - `Player` and `Enemy` had separate, parallel classes with duplicated movement logic (`core_movement()` in both `PlayerState` and `EnemyState`).
  - Enemy states tightly coupled high-level AI decisions (wait timers, aiming, target selection, transition decisions) directly with physical body actions (animations, movement physics, projectile spawning).
  - This prevented reusing abilities/actions between player and enemies and caused hit reactions (Stun) to interrupt mind logic.
- **Resolution**:
  - **Unified `Character` Base Class**:
    - Both Player and Enemies now use `Character` (`res://Character/character.gd`) extending `CharacterBody3D`.
    - Removed redundant `player.gd` and `enemy.gd`.
    - Distinct behavior is established purely through attached components and membership in the `"player"` or `"enemy"` group.
    - Added team query methods (`is_player()`, `is_enemy()`, `get_nearest_target()`).
  - **Decoupled Controller Layer**:
    - Created `PlayerInputComponent` (`res://Components/player_input_component.gd`) listening to user inputs and updating Character intents (`move_direction`, `aim_direction`, `can_dash`).
    - Created `AIStateMachine` (`res://StateMachine/ai_state_machine.gd`) extending `StateMachine` to manage AI mind behaviors (`AIWait`, `AIMeander`, `AIPursue`) that issue movement and attack commands to the Character body.
    - Created `ProjectileSpawnerComponent` (`res://Components/projectile_spawner_component.gd`) to handle ranged weapon projectile spawning decoupled from Character logic.
  - **Physical Body State Machine**:
    - Created `CharacterState` (`res://StateMachine/character_state.gd`) unifying core movement, floor checks, knockback, and velocity decay.
    - `EnemyMove` manages physical locomotion and animation blending without decision-making.
    - `EnemyAttack`, `EnemyStun`, `EnemyFall`, and `EnemyDefeat` execute physical animations and body reactions independently.
    - Dual state machines run concurrently: taking damage or entering Stun executes purely on the physical body without breaking the AI mind.
  - **Verification**:
    - Refactored all 33 parts of `test/test_enemy_base.gd`.
    - Added dedicated automated test suite `test/test_character_and_ai.tscn` verifying unified Character class, groups, intent vectors, dual state machines, stun recovery, and projectile spawning.
    - All 13 test suites pass cleanly with exit code 0 (`python run_tests.py`).

---

## 3. `ShakeCamera3D` Idle CPU Optimization [RESOLVED]
- **Status**: Completed. `ShakeCamera3D` now gates physics processing on trauma level, eliminating per-tick noise sampling and offset writes while idle.
- **Problem**:
  - `ShakeCamera3D._physics_process()` executes every single tick regardless of trauma level, continually generating FastNoiseLite noise values and modifying camera offsets even when `trauma == 0.0`.
- **Resolution**:
  - Added a typed setter on the exported `trauma` property: assigning a value `> 0.0` calls `set_physics_process(true)`; assigning `0.0` resets `h_offset`/`v_offset` and calls `set_physics_process(false)`. This covers both `quick_shake()` (whose decay Tween writes through the setter) and direct `trauma` assignments.
  - `quick_shake()` explicitly enables physics processing up front so the first shake frames run even before the Tween's `.from()` value applies.
  - `_ready()` initializes processing state from the starting trauma (`set_physics_process(trauma > 0.0)`), and `_physics_process()` disables itself as a safety net once trauma reaches `0.0` and offsets are reset.
  - Extended `test/test_shake_camera.gd` with idle/shake/decay assertions on `is_physics_processing()` plus direct-assignment setter gating coverage.

---

## 4. Data-Driven Attack System (`AttackData` Resources)
- **Problem**:
  - Attacks and combos are currently hardcoded with string names (`"SlashAttack"`, `"StabAttack"`, `"SpinAttack"`, `"RangedAttack"`), with combo branches and animation timings embedded directly into individual state scripts and scene nodes.
- **Refactoring Options**:
  - Create a custom `AttackData` resource (storing animation state name, damage, knockback, combo window, and audio stream).
  - Feed attack sequences into a single modular `AttackState` that executes whatever `AttackData` is queued, making it easy to create new weapon types and enemy attack patterns without writing new state scripts.

---

## 5. Rig & Bone Attachment Decoupling
- **Problem**:
  - Animated models (`animated_player.tscn` vs `animated_enemy.tscn`) have tightly coupled skeleton bone attachments (`WeaponSlot`, `RightFootBone`, `LeftFootBone`).
  - Reusing animations across different skeletons caused errors whenever an animation method or transform track referenced an attachment bone that was not yet duplicated into the scene.
- **Refactoring Options**:
  - Standardize socket attachments via an automated setup script or a dedicated `EquipmentManager` / `CharacterVisuals` component that programmatically binds attachment bones upon initialization.
  - Decouple gameplay logic (hitboxes, audio emission) from animation method tracks where possible, using animation events, timers, or explicit state cues.

---

## 6. Signal Lifecycle & Redundant Disconnections in States [RESOLVED]
- **Status**: Completed. Established a uniform signal lifecycle pattern: one-shot wiring via `State.connect_one_shot()` in `enter()`, cleanup via `State.disconnect_safe()` in `exit()` and early-cancel paths.
- **Problem**:
  - Multiple state scripts connect to signals using `ConnectFlags.CONNECT_ONE_SHOT` (e.g., `animation_finished.connect(..., CONNECT_ONE_SHOT)`), but also defensively call `disconnect(...)` in `exit()`.
  - This leads to potential disconnection warnings or unnecessary boilerplate guards across states.
- **Resolution**:
  - Added two documented helpers on the `State` base class (`res://StateMachine/state.gd`), inherited by every state: `connect_one_shot(sig, callback)` (guarded one-shot connect) and `disconnect_safe(sig, callback)` (guarded disconnect, silent no-op when already disconnected, e.g. after a one-shot fired).
  - Converted all four one-shot sites to the helpers: `AIWait` (wait timer), `EnemyAttack` / `EnemyStun` / `PlayerAttack` (`animation_finished`). `PlayerAttack`'s persistent `attack_timer` wiring keeps its plain `connect()` (by design) but now uses `disconnect_safe()` for both `exit()` and dash-cancel cleanup.
  - Note: the `exit()` disconnects are load-bearing, not redundant — `StateMachine._transition_to_next_state()` does not filter stale emitters, so an interrupted state (dash-cancel, stun) must unwire `animation_finished` or the late signal would force a spurious transition.
  - Added `test/test_signal_lifecycle.tscn` covering helper idempotence (no duplicate connects, fires once, safe no-op disconnect) and a dash-cancel regression test asserting exit unwires `animation_finished` and no stale transition occurs afterward. Negative control verified: with the `exit()` cleanup removed, the suite fails at the wiring assertion.
  - All 14 test suites pass cleanly with exit code 0 (`python run_tests.py`).

---

## 7. Distance-to-Player Calculation (Distance Squared Optimization) [RESOLVED]
- **Status**: Completed. Verified the per-tick proximity checks already use `distance_squared_to()` (adopted during the #2 refactor: `Character.get_nearest_target()`, `AIMeander`, `AIPursue`, all comparing against squared `attack_range` thresholds); removed the last remaining `distance_to()` call, the caller-less `Character.distance_to_character()` helper.
- **Problem**:
  - In `Enemy.distance_to_player()` and `EnemyMeander.physics_update()`, proximity checks use `global_position.distance_to(player.global_position) <= attack_range`.
  - `distance_to()` performs a square root operation ($\sqrt{\Delta x^2 + \Delta y^2 + \Delta z^2}$) on every physics tick for each active enemy.
  - As enemy density increases, running repeated square root calculations in GDScript every tick incurs unnecessary CPU overhead.
- **Refactoring Options**:
  - Switch to `distance_squared_to()`:
    ```gdscript
    func distance_squared_to_player() -> float:
        if not is_instance_valid(player):
            return INF
        return global_position.distance_squared_to(player.global_position)
    ```
  - In `EnemyMeander`, compare against a cached squared threshold:
    ```gdscript
    @export var attack_range: float = 4.0
    var attack_range_squared: float:
        get:
            return attack_range * attack_range

    # In physics_update():
    if enemy.navigation_agent_3d.is_target_reached() or enemy.distance_squared_to_player() <= attack_range_squared:
    ```
  - This eliminates the square root calculation completely with zero impact on proximity detection accuracy.

---

## 8. Dynamic Scene References vs. Hardcoded Preloads (Wave Spawner) [RESOLVED]
- **Status**: Completed. Went beyond the item's scope: eliminated every hardcoded asset reference from production scripts and turned `GlobalVars` into an autoload scene acting as a central, editor-editable scene/resource registry.
- **Problem**:
  - `WaveObjective` (and similar spawner systems) hardcodes scene preloads in script constants (`const RANGED_ENEMY: PackedScene = preload(...)` / UID strings).
  - Hardcoding scene paths or UIDs directly in scripts tightly couples the spawner to a specific enemy type, preventing reuse across different levels or encounter designs.
  - Level designers cannot swap enemy types, adjust wave compositions, or add new enemy variants in the inspector without modifying or duplicating scripts.
- **Resolution**:
  - **`GlobalVars` autoload scene**: new `Singletons/global_vars.tscn` (root `Node` + existing script, still no `class_name` so all `GlobalVars.*` call sites work); `project.godot` autoload repointed from `.gd` to `.tscn`, following the `SceneTransition` precedent. The four const preloads became documented `@export`s (`difficulty_curve`, `upgrade_damage/health/speed`) plus new registry exports (`enemy_melee_scene`, `enemy_ranged_scene`, `enemy_projectile_scene`, `fireball_hit_scene`, `damage_number_scene`, `upgrade_shop_scene`); `upgrades` is built from the upgrade exports in `_ready()`.
  - **Consumer rewiring (behavior unchanged)**: `WaveObjective` consts → `@export var enemy_scenes: Array[PackedScene]` with registry fallback (per-level override now possible); `VfxManager` reads `GlobalVars.damage_number_scene` (stays a script autoload); `EnemyProjectile` reads `GlobalVars.fireball_hit_scene` (runtime-spawned, so no local export possible); `ProjectileSpawnerComponent.projectile_scene` default is now `null` with registry fallback; `SceneTransition.levels` is now `@export` (editable in its scene); `ExitPoint` shop fallback string → `@export shop_fallback_scene` with registry fallback.
  - Verified zero `preload(`/`load("res://...")` literals remain in production scripts; test-harness `load()`s intentionally kept as asset oracles, with `test_enemy_base.gd` wiring assertions updated to the new export names (including a non-null check over the whole registry).
  - All 14 test suites pass cleanly with exit code 0 (`python run_tests.py`).

---

## 9. Domain-Specific Singletons vs. God-Object `GlobalVars` [RESOLVED]
- **Status**: Completed. `GlobalVars` is now a pure asset registry; progression and UI input live in dedicated autoloads. (Note: this item predates the `VfxManager`/`SceneTransition` autoloads and the #8 registry work — the split below builds on that state.)
- **Problem**:
  - `GlobalVars` serves as a generic "god object" catch-all singleton, accumulating disparate responsibilities (level progression, enemy count formulas, run state, and potentially future player stats or audio).
  - Mixing multiple unrelated domains into a monolithic global script violates the Single Responsibility Principle (SRP), obscures system dependencies, and complicates unit testing.
- **Resolution**:
  - **`ProgressionState`** (new script autoload `Singletons/progression_state.gd`): owns `difficulty_level` (renamed from `level`), `advance_level()`, `reset_run()`, and `get_enemy_count()` (sampled from the `GlobalVars.difficulty_curve` registry asset). Call sites migrated: `Character.reset_game_state()`, `ExitPoint`, `WaveObjective`.
  - **`UI`** (new script autoload `Singletons/ui.gd`): owns fullscreen state/toggling, the `ui_toggle_fullscreen` input event, and `PROCESS_MODE_ALWAYS`; designated home for future global menu flow (none exists yet — no menu code was found to migrate).
  - **`GlobalVars`**: registry exports + derived `upgrades` array only; fullscreen/input/level/difficulty code removed. No new `EventBus`/`EncounterDirector`/`ProjectileManager` — deferred until pooled projectiles or cross-system events create real demand.
  - Every global (`GlobalVars`, `ProgressionState`, `UI`, `VfxManager`, `SceneTransition`) now carries a docstring stating its autoload access name and unique responsibilities.
  - All 14 test suites pass cleanly with exit code 0 (`python run_tests.py`).

---

## 10. Projectile & VFX Scene Tree Ownership (Decouple from Spawner Lifecycle) [RESOLVED]
- **Status**: Completed. Projectiles and impact effects now parent to the world container via `VfxManager`, surviving shooter removal. (Note: this item predates the #2 refactor — `_on_weapon_slot_ranged_attack()` no longer exists; spawning lives in `ProjectileSpawnerComponent`. Verified nothing despawns enemies today, so this was preventive.)
- **Problem**:
  - `RangedEnemy` currently adds spawned projectiles directly as its own children (`add_child(projectile)` in `_on_weapon_slot_ranged_attack()`).
  - While `EnemyProjectile` uses `top_level = true` so its position is transformed independently in world coordinates, its scene tree lifecycle is still tightly bound to the enemy node.
  - In `enemy_projectile.gd`, `hit_effect()` compounds this by adding the `FireballHit` impact VFX node as a child of its parent (`get_parent().add_child(fireball)`), which also attaches the particles and sound directly beneath the enemy.
  - This works for now only because defeated enemies currently remain in the scene tree indefinitely without being despawned. Once enemy despawning, death cleanup (`queue_free()`), or enemy object pooling is implemented, despawning an enemy will immediately and prematurely delete any active in-flight projectiles and cut off playing fireball impact visual/audio effects.
- **Refactoring Options**:
  - **Spawn into Dedicated Level / World Container**:
    - Projectiles and impact VFX should be added to a dedicated world-space container node (e.g., an `Entities` or `Projectiles` node in the active level, or `get_tree().current_scene`).
    - *Benefits*: In-flight projectiles and exploding particles survive the death or removal of the actor that spawned them, maintaining visual continuity and correct physics simulation.
  - **Signal-Driven / Service-Driven Spawning (`ProjectileManager`)**:
    - Instead of actors directly instantiating scenes and adding them to the hierarchy, actors emit a spawn request signal (e.g. `projectile_spawn_requested(scene, transform, velocity)`) or call a centralized manager service.
    - *Benefits*: Decouples actors from scene management, facilitates centralized projectile pooling to eliminate allocation spikes, and standardizes collision layer assignment.
- **Resolution**:
  - Chose the dedicated-container option without a new autoload: `VfxManager.spawn_world_entity()` parents nodes to `current_scene` (fallback: scene root). It owns placement only, never gameplay logic — no `ProjectileManager` was created (a projectile-owning manager would just re-mix gameplay concerns in a new home).
  - `ProjectileSpawnerComponent` instantiates as before but parents via the helper and assigns the new `EnemyProjectile.shooter` reference; `hit_effect()` parents `FireballHit` via the same helper. Self-collision guards compare against `shooter` instead of `get_parent()`. Damage numbers remain screen-space children of `VfxManager`.
  - Updated `test_character_and_ai.gd` and `test_enemy_base.gd` parenting assertions to the world container (plus `shooter`-reference checks and stray-projectile cleanup); `top_level`, damage, and cleanup assertions unchanged.
  - All 14 test suites pass cleanly with exit code 0 (`python run_tests.py`).

---

## 11. File & Resource Naming Consistency (`snake_case` vs. `PascalCase`) [RESOLVED]
- **Status**: Completed. All files and resources (`.gd`, `.tscn`, `.tres`) across `Components/`, `Levels/`, `Singletons/`, `StateMachine/`, `UserInterface/`, and `Assets/Shaders/` have been standardized to uniform `snake_case` following official Godot conventions. All scene `ext_resource` paths, preload/load calls, autoload configurations, `.uid` files, and test suites have been updated and verified.
- **Problem**:
  - The project previously exhibited mixed and inconsistent naming conventions across folders, scenes, and scripts (e.g. `HealthComponent.gd`, `GlobalVars.gd`, `DamageNumber.tscn`, `LevelTemplate.tscn`, state scripts in PascalCase vs. other scripts in snake_case).
- **Resolution**:
  - Standardized on official Godot conventions:
    - Scripts: `health_component.gd`, `knockback_component.gd`, `attack_component.gd`, `global_vars.gd`, `vfx_manager.gd`, state scripts (`player_dash.gd`, `enemy_meander.gd`, etc.).
    - Scenes: `level_template.tscn`, `damage_number.tscn`, `upgrade_shop.tscn`.
    - Shaders / Materials: `dash.tres`, `fire.tres`.
    - Maintained PascalCase for `class_name` definitions and Scene Tree Node names as recommended by Godot style guidelines.
    - Updated all UID files and resource references cleanly; all 12 test suites pass.

---

## 12. Dedicated Hurtbox & Hitbox Pattern (Decouple Damage from Physics Bodies & String Node Lookups) [RESOLVED]
- **Status**: Completed. Implemented the recommended dedicated-`Hurtbox` option: every character carries a hurtbox, attackers call `receive_hit()`, and hitboxes mask only the hurtbox layer.
- **Problem**:
  - `AttackComponent` currently inspects hit colliders directly from a `ShapeCast3D` using runtime string lookups: `collider.has_node("HealthComponent")` and `collider.has_node("KnockbackComponent")`.
  - This introduces several architectural and performance drawbacks:
    1. **Performance Overhead**: Calling `has_node()` and `get_node()` on colliders builds `NodePath` objects, hashes strings, and traverses scene tree children on every collision tick of an active attack.
    2. **Violation of the Open/Closed Principle**: The attacker's `AttackComponent` must explicitly know about every possible reactive component on the target (`HealthComponent`, `KnockbackComponent`, and future additions like `StatusEffectsComponent`, `ArmorComponent`, etc.). Adding a new reaction requires modifying `AttackComponent`.
    3. **Coupled Movement & Damage Collisions**: Weapons collide directly with the entity's primary movement collider (`CharacterBody3D`). This makes it difficult to implement invulnerability frames (e.g. during a dash or roll), localized damage zones (weak points, headshots, shields), or distinct damage boundaries separate from wall/floor navigation collision.
- **Refactoring Options**:
  - **Dedicated `Hurtbox` Area3D Component (Recommended)**:
    - Create a `Hurtbox` class (`extends Area3D`) assigned to a dedicated collision layer (e.g., `Hurtboxes`).
    - The `Hurtbox` holds direct, typed references to its actor's `health_component`, `knockback_component`, and any defensive stats.
    - Weapons/projectiles (`Hitbox` components or `ShapeCast3D`) only mask the `Hurtbox` layer, completely ignoring the root `CharacterBody3D`.
    - On collision, the attacker calls a single typed method:
      ```gdscript
      hurtbox.receive_hit(damage, knockback)
      ```
    - The `Hurtbox` encapsulates all response logic: delegating damage to `HealthComponent`, applying momentum to `KnockbackComponent`, triggering invulnerability flash/timers, and dispatching hit reactions.
  - **Entity-Level `take_hit()` Method Interface (Lightweight Alternative)**:
    - If dedicated `Area3D` nodes are not desired for simple props, define a standardized `take_hit(damage: float, knockback: Vector3)` method on characters or destructible actors.
    - The attacker performs a single cached symbol check:
      ```gdscript
      if collider.has_method(&"take_hit"):
          collider.take_hit(damage, knockback)
      ```
  - *Benefits*:
    - **Zero String Tree Lookups**: Replaces runtime string lookups with compile-time typed method calls or fast native symbol checks (`&"take_hit"`).
    - **True Decoupling**: Attackers only know that they applied force and damage; targets decide how they react.
    - **Flexible Combat Mechanics**: Enables i-frames (by disabling the hurtbox collision shape while keeping movement collision active), precision hitboxes, and non-character destructible props (crates, barrels, doors) without special-case logic in `AttackComponent`.
- **Resolution**:
  - New `Components/hurtbox.gd` (`class_name Hurtbox extends Area3D`) with typed `@export` refs and `receive_hit(damage, knockback) -> bool` delegating to `HealthComponent`/`KnockbackComponent`. New `Hurtboxes` physics layer 7 (64); hurtboxes sit on layer 64 / mask 0.
  - `Player` and `EnemyBase` (inherited by melee + ranged) each gained a `Hurtbox` + `CollisionShape3D` reusing the body capsule, with scene-wired component refs. Hitbox masks are now hurtbox-only: player `2→64`, melee `16→64`, projectile `17→65` (layer 1 kept for wall impacts).
  - `AttackComponent` is area-driven (`area is Hurtbox` checks, typed `deal_damage_to(Hurtbox, ...)`); `body_entered` wiring removed. New `wielder` resolution (hitbox ancestry walk) excludes the attacker's own overlapping hurtbox. `EnemyProjectile` ignores `Character` bodies (hurtbox event owns damage), detonates on other bodies, and checks `Hurtbox`-vs-`shooter` on areas.
  - Note: knockback now applies together with damage inside `receive_hit()` (previously it could apply to healthless targets); no such targets exist. Dash i-frames not added (future hook documented on `Hurtbox`); `world_boundary.gd` keeps its once-per-fall lookup.
  - Tests: Part 30/31 mask + hurtbox presence/wiring assertions, `deal_damage_to` now takes the dummy's hurtbox. Required a headless `godot --import` rescan to register the new global class. All 14 suites pass (`python run_tests.py`).
  - Follow-up fixes: hurtbox layers split per team (`PlayerHurtbox` 64 / `EnemyHurtbox` 128) after melee gained the ability to hit other enemies — melee hitboxes now mask the opposing team only (player `128`, enemy `64`), projectiles mask walls + both teams (`193`, friendly fire kept). `Hurtbox.receive_hit()` rejects targets at `current_health <= 0.0` since corpses keep an enabled hurtbox shape after the body shape is disabled on defeat. Covered by new Part 34 (team masks, live melee-vs-enemy/player overlap, dead-target rejection; both negative controls verified).

---

## 13. Data-Driven Shop Upgrades (`UpgradeResource` Resources) [RESOLVED]
- **Status**: Completed. Replaced multiple separate upgrade scenes and custom script inheritance with a single presentation scene (`UserInterface/upgrade_icon.tscn`) dynamically driven by custom `UpgradeResource` assets (`.tres`).
- **Problem**:
  - Each upgrade was implemented as a separate Godot PackedScene (`upgrade_damage.tscn`, `upgrade_speed.tscn`, `upgrade_health.tscn`), with health requiring its own subclass script (`upgrade_health.gd`).
  - This created scene sprawl, coupled gameplay data with scene hierarchy, and required creating new scenes and scripts for every stat addition.
- **Resolution**:
  - **`UpgradeResource` Base Class**:
    - Created `res://UserInterface/upgrade_resource.gd` (`class_name UpgradeResource extends Resource`).
    - Encapsulates `title`, `text_template`, `upgrade_type` (`STAT` vs `MAX_HEALTH`), `stat_name`, `stat_bonus`, and optional `icon`.
    - Implements `get_current_value(player)`, `get_upgraded_value(player)`, `format_description(player)`, and `apply(player)`.
  - **Data Assets (`.tres`)**:
    - Created `upgrade_damage.tres` (+50% damage stat).
    - Created `upgrade_speed.tres` (+1.5 m/s movement speed).
    - Created `upgrade_health.tres` (+20 HP max health and current health).
  - **Single UI Scene & Decoupled Shop**:
    - `UserInterface/upgrade_icon.tscn` is now the single presentation card scene for all upgrades.
    - `upgrade_icon.gd` accepts an `UpgradeResource` via `set_upgrade_resource()` or `@export var upgrade_resource`, updating title and description dynamically and delegating application upon click.
    - `upgrade_shop.gd` exports `upgrade_card_scene: PackedScene` (fallback to `GlobalVars.upgrade_icon_scene`) and `available_upgrades: Array[UpgradeResource]` (fallback to `GlobalVars.upgrades`).
    - `GlobalVars` exports `upgrade_icon_scene` and the three `UpgradeResource` assets.
  - **Cleanup**:
    - Deleted `upgrade_damage.tscn`, `upgrade_speed.tscn`, `upgrade_health.tscn`, `upgrade_health.gd`, and `upgrade_health.gd.uid`.
  - **Verification**:
    - Updated Part 11 and Part 13 in `test/test_enemy_base.gd` to test dynamic resource assignment, formatted text output, stat modifications, button disabling, and repeated click prevention.
    - All 35 parts of `test_enemy_base.tscn` pass cleanly.


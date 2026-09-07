# Post-Course Refactoring & Scalability Backlog

This document tracks architectural improvements, optimizations, and technical debt to address after completing the course lessons. While following the course, we adhere closely to the instructor's implementation to stay aligned with the tutorial; this list outlines items to refactor toward a clean, production-ready codebase.

---

## 1. Projectile Collision & Performance (ShapeCast vs. Event-Driven)
- **Problem**: 
  - `EnemyProjectile` currently extends `ShapeCast3D` with `enabled = true` by default.
  - In `_physics_process()`, the script updates `global_position` and calls `attack_component.deal_damage()`, which invokes `attack_shapecast.force_shapecast_update()`.
  - This results in **duplicate collision sweeps per physics tick** (the engine's automatic sweep at the start of the tick at the old position + the manual `force_shapecast_update()` sweep at the new position).
  - Furthermore, polling `is_colliding()` and looping through collisions in GDScript every physics tick introduces unnecessary interpreter overhead across multiple projectiles.
- **Refactoring Options**:
  1. **Event-Driven via `Area3D`**:
     - Change projectiles from `ShapeCast3D` to `Area3D`.
     - Connect to the `body_entered` / `area_entered` signals.
     - *Benefits*: Collision checks run entirely in Godot's compiled C++ physics pipeline. Zero GDScript collision code runs during flight when flying through empty space; script execution only triggers on actual impacts.
  2. **Single-Sweep `ShapeCast3D` (Anti-Tunneling)**:
     - If continuous shape-sweeping is needed for fast-moving projectiles to prevent tunneling through thin colliders, keep `ShapeCast3D` but set `enabled = false`.
     - Move the node in `_physics_process()`, call `force_shapecast_update()` once, and process hits.
  3. **Decouple `AttackComponent`**:
     - Refactor `AttackComponent` so it does not strictly expect a `ShapeCast3D` parent, allowing it to work with `Area3D`, melee weapon hitboxes, or standalone collision events.

---

## 2. Character & State Machine Architecture (Decoupling AI from Body Action States)
- **Problem**:
  - `Player` and `Enemy` have separate, parallel state machines with duplicated movement logic (`core_movement()` in both `PlayerState` and `EnemyState`).
  - Enemy states tightly couple high-level AI decisions (wait timers, aiming, target selection, transition decisions) directly with physical body actions (animations, movement physics, projectile spawning).
  - This prevents reusing abilities/actions between player and enemies, creates a combinatorial explosion of states for different AI behaviors, and makes advanced tactics (kiting, fleeing, utility scoring) difficult to implement.
- **Refactoring Options**:
  - **Controller Layer (The Mind)**:
    - Separate decision-making into an `AIController` (or Behavior Tree / Utility AI) and a `PlayerController`.
    - Both controllers output standardized high-level intents: `move_intent(direction)`, `aim_intent(target)`, `try_activate_ability(ability_name)`.
  - **Character & Ability Layer (The Body)**:
    - The character's state machine manages only physical body commitments and abilities: `Idle`, `Move`, `Attack`, `Dodge`, `Stunned`, `Defeated`.
    - States handle animation playback, root motion, and hitbox/projectile activation windows. They report completion back to the character/controller (e.g. `action_finished` signal) rather than deciding what state to transition to next.
    - Create a unified character base class / component structure shared by player and enemies.

---

## 3. `ShakeCamera3D` Idle CPU Optimization
- **Problem**:
  - `ShakeCamera3D._physics_process()` executes every single tick regardless of trauma level, continually generating FastNoiseLite noise values and modifying camera offsets even when `trauma == 0.0`.
- **Refactoring Options**:
  - Disable physics processing by default via `set_physics_process(false)`.
  - Enable processing in `add_trauma()` when trauma is applied, and call `set_physics_process(false)` as soon as trauma decays back to `0.0` and offsets are reset.

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

## 6. Signal Lifecycle & Redundant Disconnections in States
- **Problem**:
  - Multiple state scripts connect to signals using `ConnectFlags.CONNECT_ONE_SHOT` (e.g., `animation_finished.connect(..., CONNECT_ONE_SHOT)`), but also defensively call `disconnect(...)` in `exit()`.
  - This leads to potential disconnection warnings or unnecessary boilerplate guards across states.
- **Refactoring Options**:
  - Establish a uniform, clean signal lifecycle pattern across all state machines (either rely consistently on `CONNECT_ONE_SHOT` with safe cleanup helpers, or manage connection lifetime cleanly in `enter()` / `exit()`).

---

## 7. Distance-to-Player Calculation (Distance Squared Optimization)
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

## 8. Dynamic Scene References vs. Hardcoded Preloads (Wave Spawner)
- **Problem**:
  - `WaveObjective` (and similar spawner systems) hardcodes scene preloads in script constants (`const RANGED_ENEMY: PackedScene = preload(...)` / UID strings).
  - Hardcoding scene paths or UIDs directly in scripts tightly couples the spawner to a specific enemy type, preventing reuse across different levels or encounter designs.
  - Level designers cannot swap enemy types, adjust wave compositions, or add new enemy variants in the inspector without modifying or duplicating scripts.
- **Refactoring Options**:
  - **Exported `PackedScene` Properties**:
    - Replace hardcoded `preload` constants with an exported property:
      ```gdscript
      @export var enemy_scene: PackedScene
      ```
      or an array for multi-enemy encounters:
      ```gdscript
      @export var enemy_scenes: Array[PackedScene]
      ```
  - **Data-Driven Wave Resources (`WaveData`)**:
    - Encapsulate wave parameters into custom `Resource` definitions (`WaveData`), configuring enemy scenes, spawn counts, delays, and weights directly in the inspector:
      ```gdscript
      @export var waves: Array[WaveData]
      ```
    - *Benefits*: Decouples spawner logic from concrete scene assets, allows rapid level design iteration entirely in the inspector, and facilitates varied encounter design.

---

## 9. Domain-Specific Singletons vs. God-Object `GlobalVars`
- **Problem**:
  - `GlobalVars` serves as a generic "god object" catch-all singleton, accumulating disparate responsibilities (level progression, enemy count formulas, run state, and potentially future player stats or audio).
  - Mixing multiple unrelated domains into a monolithic global script violates the Single Responsibility Principle (SRP), obscures system dependencies, and complicates unit testing.
- **Refactoring Options**:
  - **Decompose into Dedicated, Purpose-Driven Services**:
    - **`RunManager` / `ProgressionService`**: Manages the current level index, active run seed, run difficulty tier, and progression lifecycle (`level_finished`, `run_won`, `run_lost`).
    - **`EncounterDirector` / `SpawnDirector`**: Handles encounter scaling logic, wave budgeting, and enemy distribution formulas based on level progression and difficulty.
    - **`EventBus`**: A lightweight global signal hub (Observer pattern) allowing subsystems to publish and subscribe to gameplay events without referencing concrete system singletons directly.
  - *Benefits*: Enforces clean architectural boundaries, keeps global state focused and auditable, and ensures systems can be tested or swapped independently.

---

## 10. Projectile & VFX Scene Tree Ownership (Decouple from Spawner Lifecycle)
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




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

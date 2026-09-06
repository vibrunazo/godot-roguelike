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

## 2. Character & State Machine Architecture
- **Problem**:
  - `Player` and `Enemy` have separate state machines and duplicated movement code (e.g. `core_movement()` in both `PlayerState` and `EnemyState`).
- **Refactoring Options**:
  - Create a unified character base class (or controller/component architecture) shared by both player and enemies.
  - Make state machine movement logic generic or controller-driven so AI controllers and player input controllers plug into the same movement state logic.

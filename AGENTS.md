# AGENT.md - Project Context & Guidelines

## 1. Project Overview
- **Engine**: Godot 4.7.2 stable official (Windows, Forward+ / D3D12).
- **Genre**: 3D Top-Down Action Roguelite (based on GameDev.tv Godot 3D Course, already completed).
- **Phase**: Adding custom gameplay improvements, combat polish, and balance.

---

## 2. Mandatory Coding Guidelines
1. **Strict GDScript Typing**:
   - `warnings/untyped_declaration=1` is enforced in `project.godot`.
   - Every variable, parameter, and function return type must be explicitly typed (e.g. `var x: float = 0.0`, `func foo(bar: int) -> void:`).
2. **Documentation Integrity**:
   - Preserve and maintain all docstrings (`## ...`) and comments on classes, exported variables, and functions.
3. **Git Commits**:
   - The user manages git commits. **Never run `git commit` or `git push` unless explicitly told so by the user**.

---

## 3. Testing & CLI Execution Policy (CRITICAL TIMEOUT RULES)

### Why Bare Commands Are Forbidden
Godot does not exit on GDScript compilation errors, cyclic preloads, or unhandled runtime exceptions. If an error occurs, Godot prints the error to the console, skips the rest of the function, and idles indefinitely. Because `--quit-after` only counts process frames after the engine initializes, scripts that fail to compile or hit missing autoloads will hang the terminal forever.

> **NEVER execute bare `godot --headless` commands directly under any circumstances.**
>
> All headless commands must run through an external OS watchdog that forcefully terminates the process after a hard timeout (60 seconds max).

### Approved Test Execution Commands

- **Run Full Test Suite (Preferred):**
  ```bash
  python run_tests.py
  ```

- **Run a Single Test Suite via Python Runner:**
  ```bash
  python run_tests.py test/test_combo_and_dash_cancel.tscn
  ```


- **Running Scratch / Diagnostic Scripts via Python One-Liner:**
  ```bash
  python -c "import subprocess; subprocess.run(['godot', '--headless', '--path', '.', '--quit-after', '60', '-s', 'scratch/my_script.gd'], timeout=10)"
  ```

---

## 4. Architecture & Key Patterns
- **State Machine**:
  - Located in `StateMachine/`. States extend `PlayerState` or `EnemyState`.
  - Transitions emit `finished.emit(next_state_name, data_dict)`.
- **Combat Components**:
  - `AttackComponent`: Sits under an `Area3D` hitbox or projectile. Listens to `body_entered` / `area_entered` signals to deal damage and knockback, handles screen shake, and manages `rehit_interval`.
  - `KnockbackComponent`: Handles physics impulse and exponential decay (`lerp` with `exp(-decay * delta)`). Active if magnitude > 1.0.
  - `HealthComponent`: Manages current/max health, damage taking, and `defeat` signal.
  - `WeaponSlot`: Extends `BoneAttachment3D`. Has exported `hitbox: Area3D`. Animating `WeaponSlot:enabled` automatically toggles `hitbox.monitoring` and `hitbox.monitorable`.
- **Hit Timing & Multi-Hit Logic**:
  - `AttackComponent.rehit_interval`: Minimum interval (seconds) before a target can take damage again.
  - If `<= 0.0`, target is hit once per attack until `reset_exceptions()`.
  - If `> 0.0`, target exception is cleared after `rehit_interval` expires (used for SpinAttack).

---

## 5. Animation & Character Mesh Extraction Guide

### Source Asset Locations
- **Animation GLBs**: `Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/` (e.g. `Rig_Medium_CombatMelee.glb`, `Rig_Medium_General.glb`, `Rig_Medium_Movement.glb`).
- **Character Model GLBs**: `Assets/KayKit_Assets/KayKit_GameDevTV_Enemies_Character_Pack_1.0/Characters/gltf/` (e.g. `Enemy_Medium.glb`).
- **Extracted `.res` Destination**: `Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/<AnimationName>.res`.

### Headless Animation Extraction Recipe
Godot's GUI "Save to File" import option is unavailable to headless CLI agents. Instead, load the source GLB scene in a temporary GDScript, duplicate the target animation, and save it via `ResourceSaver` (wrapped in a Python OS watchdog):

```python
python -c "
import subprocess
script = '''
extends SceneTree
func _init() -> void:
    var glb: Node3D = load(\"res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Rig_Medium_CombatMelee.glb\").instantiate() as Node3D
    var ap: AnimationPlayer = glb.find_child(\"AnimationPlayer\", true, false) as AnimationPlayer
    var anim: Animation = ap.get_animation(\"Melee_2H_Attack_Chop\").duplicate() as Animation
    ResourceSaver.save(anim, \"res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_2H_Attack_Chop.res\")
    glb.queue_free()
    quit(0)
'''
with open('scratch_extract.gd', 'w') as f: f.write(script.strip())
subprocess.run(['godot', '--headless', '--path', '.', '-s', 'scratch_extract.gd'], timeout=10)
import os; os.remove('scratch_extract.gd')
print('Extracted successfully!')
"
```

### The 3 Mandatory Combat Animation Tracks
When adding any attack animation for the Player or Melee Enemies, the animation `.res` MUST include the following project-specific tracks to interact with the combat systems:

1. **`Rig_Medium/Skeleton3D/WeaponSlot:enabled`** (Value track, discrete update):
   - `0.0s`: `false` (disabled during windup)
   - Strike apex: `true` (enables hitbox `ShapeCast3D`)
   - Strike bottom: `false` (disables hitbox during recovery)
2. **`Rig_Medium/Skeleton3D/WeaponSlot:attack_mode`** (Value track, discrete update):
   - Key: `1` for `Slash`, `2` for `Stab`.
3. **`Rig_Medium/Skeleton3D/WeaponSlot:vfx_threshold`** (Value track, continuous update):
   - Eased float curve (`1.0` -> `0.0` -> `1.0`) driving the slash trail shader sweep.

### AnimationTree & Library Integration
1. In `animated_player.tscn` or `animated_enemy.tscn`, add the `.res` file to the `PlayerAnimations` or `EnemyAnimations` library on `AnimationPlayer`.
2. In the `AnimationTree` root state machine (`AnimationNodeStateMachine`):
   - Add an `AnimationNodeAnimation` node pointing to `LibraryName/AnimationName`.
   - Add transition from `WalkSpace` -> `AttackState`: `advance_mode = 1` (manual trigger).
   - Add transition from `AttackState` -> `WalkSpace`: `switch_mode = 2` (At End), `advance_mode = 2` (Auto), `xfade_time = 0.2`.

---

## 6. Level Creation & Environment Guidelines

These are practical conventions and lessons learned from the course lectures rather than rigid rules:

### 1. Level Inheritance & Template Structure
- Create new levels as inherited scenes from `res://Levels/level_template.tscn` (`Levels/level_template.tscn`).
- The template already provides the standard lighting (`DirectionalLight3D`), sky environment (`WorldEnvironment`), wave spawner (`WaveObjective`), fall-kill plane (`WorldBoundary`), and exit portal (`ExitPoint`).

### 2. GridMaps & Metrics
- **Floormap**: Uses `res://Levels/Gridmap/floormap.tres` with `cell_size = Vector3(4, 0.5, 4)`.
- **Wallmap**: Uses `res://Levels/Gridmap/wall_map.tres` with `cell_size = Vector3(2, 4, 2)`.
- Decorative litter / props can be grouped under a dedicated `Litter` (Node3D) container to keep the scene tree clean.
- Gaps in the floor serve as pits; place a `Pit` visual quad beneath gaps, and rely on `WorldBoundary` (at `y = -4`) to detect and eliminate fallen entities.

### 3. VoxelGI Baking & Coverage (Crucial)
- Every level must have its own baked `VoxelGI` data saved to `res://Levels/GlobalIlluminationData/<level_name>_voxel_gi_data.res`.
- **Volume Bounds**: Adjust the `VoxelGI` node's `transform` and `size` so the bounding box completely encloses the playable geometry, player spawn, pits, and exit door.
- **Dynamic Entities Exclusion**: Ensure dynamic entities (characters, weapons, animated props) have `gi_mode = 0` (`GI_MODE_DISABLED`) so they don't bake permanent static shadow artifacts into the global illumination.

### 4. NavigationMesh Coverage
- Ensure `NavigationRegion3D` has its `NavigationMesh` baked to cover the new floor layout.
- Verify that the navmesh wraps cleanly around wall obstacles and stays clear of pits so enemy pathfinding doesn't stall or try to walk off ledges.

### 5. Level Rotation & Exit Wiring
- Position `Player` at the starting spawn point and `ExitPoint` at the end of the dungeon.
- Ensure `WaveObjective.finished` is connected to `ExitPoint.unlock()` (wired by default in `level_template.tscn`).
- To include the new level in the random run rotation, add its scene path to `SceneTransition.levels` in `res://Singletons/scene_transition.tscn` (`Singletons/scene_transition.tscn`).




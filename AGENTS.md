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

### Worktree Rules
- Always create feature worktrees under `.worktrees/<branch-name>` inside the project root.
- Never create worktrees outside the repository tree.

---

## 3. Testing & CLI Execution Policy (CRITICAL TIMEOUT RULES)

### The Godot Hang Problem & Watchdog Requirement
Godot does not exit on GDScript compilation errors, cyclic preloads, or unhandled runtime exceptions. If an error occurs, Godot prints the error to the console, skips the rest of the function, and idles indefinitely. Because `--quit-after` only counts process frames after the engine initializes, scripts that fail to compile or hit missing autoloads will hang the terminal forever.

> **When launching Godot, never execute bare `godot` commands without an external OS timeout.**
>
> All Godot invocations must run through an external OS watchdog that forcefully terminates the process after a hard timeout (e.g. Python `timeout=N`).
>
> *Note*: Agents are encouraged to run whatever standard CLI commands they need (`git status`, `git diff`, Python scripts, filesystem inspection, etc.). The timeout rule applies specifically when invoking the Godot engine process.

### Built-in Project Runners & Shortcuts
Agents can write and execute whatever custom scripts or commands their task requires. For common Godot workflows, prefer using these built-in runners because they already implement watchdog timeouts, portable executable resolution, and engine validation:

- **Run Full Test Suite (Preferred):**
  ```bash
  python run_tests.py
  ```

- **Run a Single Test Suite:**
  ```bash
  python run_tests.py test/test_combo_and_dash_cancel.tscn
  ```

- **Run Scratch / Diagnostic Scripts via Watchdog Runner:**
  ```bash
  python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn
  python run_scratch.py tools/levels/dump_cells.gd --timeout 15 -- --level=Levels/level_2.tscn
  ```

- **Visual Media Capture & Recording:**
  ```bash
  python capture.py map Levels/level_1.tscn --preset isometric
  python capture.py anim Enemy/enemy_brute.tscn --state EnemyPunch --video
  python capture.py combat --player --enemy brute --action "enemy:state:EnemyPunch@15" --video
  python capture.py test test/test_combo_and_dash_cancel.tscn --video
  ```
  *(See `CAPTURE.md` for full command line options and syntax).*

### Critical Engine Invariants for Standalone GDScripts (`-s`)
Scripts executed standalone via Godot's `-s` flag **strictly require** two rules:
1. **The script MUST inherit `SceneTree` (or `MainLoop`)**: e.g. `extends SceneTree`.
   - Standalone execution bypasses the scene tree root. If the script extends `Node` or `Node3D`, Godot fails to start the main loop, `--quit-after` will never count process frames, and Godot idles indefinitely.
2. **The script MUST explicitly call `quit(code)`** when done (e.g. `quit(0)`).
3. **Always use `run_scratch.py`**: It automatically validates these invariants before launching Godot and enforces an external OS watchdog timeout.

### Testing Philosophy & Invariants
- **Never assert balance values or tuning constants:** Do not test for hardcoded damage numbers, cooldown lengths, movement speeds, or specific keyboard scancodes.
- **Test behavioral contracts and state transitions:** 
  - Test that entering cooldown prevents reactivation until elapsed, using the node's own exported variable (e.g., `simulate_time(node.cooldown_time)`).
  - Test relative damage application (`target.health == previous_health - attack.damage`), not arbitrary final integers.
  - Test actions via `InputMap` action names (e.g., `"toggle_fullscreen"`), never physical key constants (`KEY_F`).
- **If a test fails due to intentional balance changes, the test design was flawed.** Fix the test to evaluate the mechanic dynamically, never hardcode the new value.

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
Godot's GUI "Save to File" import option is unavailable to headless CLI agents. Instead, create a temporary script extending `SceneTree` under `tools/levels/out/` (git-ignored and importer-ignored) and execute it via `run_scratch.py`:

```gdscript
# tools/levels/out/extract_anim.gd
extends SceneTree

func _init() -> void:
    var glb: Node3D = load("res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Rig_Medium_CombatMelee.glb").instantiate() as Node3D
    var ap: AnimationPlayer = glb.find_child("AnimationPlayer", true, false) as AnimationPlayer
    var anim: Animation = ap.get_animation("Melee_2H_Attack_Chop").duplicate() as Animation
    ResourceSaver.save(anim, "res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_2H_Attack_Chop.res")
    glb.queue_free()
    quit(0)
```

Run via the runner:
```bash
python run_scratch.py tools/levels/out/extract_anim.gd
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
- Prefer the scripted pipeline in `tools/levels/` over hand-editing scenes: dump/validate/pack GridMap data, assemble from a JSON spec, bake navmesh + VoxelGI. Full guide, per-tool usage, and lessons learned: `tools/levels/README.md`. Every level must pass `test/test_level_rotation_nav.tscn` (load, baked GI, navmesh coverage, spawn→exit path).

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



---

## 7. Universal Subprocess & Execution Policy (All Platforms)

To ensure scripts run reliably without hangs, pipe deadlocks, or process leaks across any operating system (Linux, WSL, macOS, Windows):

1. **Prefer Dedicated Project Runners When Applicable**:
   - **Test Suites**: `python run_tests.py [path]`
   - **Scratch / Diagnostic Scripts**: `python run_scratch.py <path> [--timeout N]`
   - **Visual Media Capture & Scenarios**: `python capture.py <subcommand>`
   - *Custom Scripts & Commands*: If a task requires custom scripts or commands not covered by the above, agents can write and run them following the guidelines below.

2. **Resolve Binaries via `shutil.which`**:
   - When calling external commands (`godot`, `ffmpeg`) from Python, resolve the executable via `shutil.which("godot") or "godot"`.
   - This cleanly and portably resolves binary locations, wrapper scripts (e.g. bash scripts on Linux/WSL), or shims without hardcoded paths or OS-specific branching.

3. **Use `shell=False` with Argument Lists**:
   - `shell=True` spawns an intermediate shell process. On timeout, Python terminates the shell while the child engine process may remain orphaned, holding standard I/O pipes open and stalling execution.
   - `shell=False` connects Python directly to the process, ensuring timeout termination forcefully kills the engine immediately.

4. **Enforce Hard OS Watchdog Timeouts**:
   - Avoid running unbounded processes; pass `timeout=<seconds>`.
   - Catch `subprocess.TimeoutExpired` explicitly to handle timeouts gracefully.

#### Portable Subprocess Pattern:
```python
import shutil
import subprocess

godot_bin = shutil.which("godot") or "godot"
cmd = [
    godot_bin,
    "--headless",
    "--path", ".",
    "--quit-after", "60",
    "-s", "tools/levels/dump_cells.gd",
]

try:
    res = subprocess.run(cmd, shell=False, capture_output=True, text=True, timeout=15)
    if res.stdout:
        print(res.stdout)
    if res.returncode != 0:
        print(f"Process failed (exit code {res.returncode}):\n{res.stderr}")
except subprocess.TimeoutExpired:
    print("ERROR: Godot process timed out and was forcefully terminated.")
```

---

## 8. Visual Media Capture & Staging Guidelines

Practical suggestions for capturing animations, combat scenarios, and level layouts efficiently:

1. **Start with the Simplest Capture Tool**:
   - For solo abilities, leap animations, attacks, or inspectable states, `python capture.py anim <scene> --state <StateName> --video` is typically the fastest approach. It provides an isolated studio, key lights, and a neutral backdrop.
   - Staging multi-entity scenarios via `python capture.py combat` is best suited for interactions that specifically require two or more characters (such as testing hit reactions, damage counters, or combo timings).

2. **Framing High-Mobility Abilities**:
   - Abilities that cover significant distance (e.g. `EnemyLeapingDodge`, dashes, leap slams) can travel outside the default camera frame.
   - Use `--cam-dist` (e.g. `--cam-dist 2.5`) and `--cam-height` to comfortably widen the framing rather than hand-crafting custom camera trajectories.

3. **Mind Internal Actor Cameras**:
   - Some character scenes (e.g. `Player.tscn`) contain built-in `Camera3D` components (`CameraRoot/ShakeCamera3D`). When these scenes enter the scene tree, their internal cameras may attempt to claim active viewport status.
   - The built-in capture runners automatically suppress actor cameras, but when writing custom staging scripts, remember to check spawned scenes to ensure actor cameras do not override the studio camera.





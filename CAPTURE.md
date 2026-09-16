# CAPTURE.md - Map, Animation & Combat Capture System

This document explains how agents and developers can capture screenshots and record videos of levels (maps), character animations, combat scenarios, and test executions.

All outputs are automatically saved directly into the `movies/` folder. Video recordings are automatically converted from raw Godot MovieMaker AVIs to optimized H.264 `.mp4` (and optional `.gif`) files via FFmpeg.

---

## 1. Quick Start

Run any capture command directly from the project root using the unified runner `capture.py`:

```bash
# 1. Take an isometric screenshot of a level
python capture.py map Levels/level_1.tscn

# 2. Take screenshots from all 5 preset angles (isometric, top-down, front, side, overview)
python capture.py map Levels/level_1.tscn --preset all

# 3. Record a 3-second video of an enemy brute attack with a target dummy and visible hitboxes
python capture.py anim Enemy/enemy_brute.tscn --state EnemyAttack --video --duration 3.0 --dummy --debug-collisions

# 4. Stage a player vs enemy combat scenario and record video
python capture.py combat --player --enemy brute --action "enemy:state:EnemyPunch@15" --video --duration 2.5

# 5. Visually record any existing or future test suite to MP4
python capture.py test test/test_combo_and_dash_cancel.tscn
```

---

## 2. Command Reference

### A. Map / Level Capture (`python capture.py map`)

Captures scenery, level layout, or gameplay across any level `.tscn` file. Automatically computes map bounding boxes from `GridMap` and meshes.

```bash
python capture.py map <level_path> [options]
```

#### Presets & Camera Angles
| Option | Description | Example |
| :--- | :--- | :--- |
| `--preset <name>` | Camera angle preset: `isometric` (default), `top_down`, `front`, `side`, `overview`, `all` | `--preset top_down` |
| `--cam-pos <X,Y,Z>` | Custom camera position in 3D world space | `--cam-pos 0,25,-15` |
| `--cam-target <X,Y,Z>` | Custom camera look-at target | `--cam-target 0,0,-20` |
| `--target-node <name>` | Automatically centers and frames a specific node in the level | `--target-node Player` |
| `--ortho` | Switches camera projection to Orthographic (architectural / 2D map view) | `--ortho` |
| `--cam-size <float>` | Orthographic camera view size | `--cam-size 35.0` |
| `--cam-fov <float>` | Camera Field of View in degrees (perspective mode) | `--cam-fov 60.0` |
| `--cam-dist <float>` | Distance multiplier relative to calculated level bounds | `--cam-dist 1.2` |
| `--cam-height <float>`| Height offset added to the camera position | `--cam-height 5.0` |

#### Debugging & Capture Options
| Option | Description | Example |
| :--- | :--- | :--- |
| `--debug-collisions` | Renders physics shapes, hurtboxes, and navigation barriers | `--debug-collisions` |
| `--freeze` | Freezes all AI state machines and physics actors (for clean static scenery shots) | `--freeze` |
| `--show-ui` | Keeps UI overlays and banners visible (automatically suppressed by default for clean captures) | `--show-ui` |
| `--video` | Records video instead of a static screenshot | `--video` |
| `--duration <sec>` | Video duration in seconds (defaults to 3.0) | `--duration 4.0` |
| `--output <path>` | Custom output destination path in `movies/` | `--output movies/mylevel.png` |
| `--gif` | Also generates an animated GIF alongside the MP4 | `--gif` |
| `--keep-avi` | Preserves the intermediate raw uncompressed AVI file | `--keep-avi` |

---

### B. Animation & Asset Capture (`python capture.py anim`)

Inspects, screenshots, or records:
1. **Character Scenes (`.tscn`)**: e.g. `Enemy/enemy_brute.tscn`, `Enemy/melee_enemy.tscn`, `Player/player.tscn`.
2. **Raw Animation Resources (`.res`)**: e.g. `Assets/.../Melee_2H_Attack_Chop.res` (mounted automatically on a matching base rig).
3. **Animation GLB Archives (`.glb`)**: e.g. `Assets/.../Rig_Medium_CombatMelee.glb`.

```bash
python capture.py anim <target_path> [options]
```

#### Key Options
| Option | Description | Example |
| :--- | :--- | :--- |
| `--state <name>` | Requests a specific `StateMachine` state (e.g. `EnemyPunch`, `EnemyAttack`, `AISlam`) | `--state EnemyPunch` |
| `--anim <name>` | Plays a specific animation by name on `AnimationPlayer` | `--anim Melee_2H_Attack_Chop` |
| `--dummy` | Spawns a target dummy in front of the character at weapon strike distance | `--dummy` |
| `--debug-collisions`| Shows cyan/magenta collision shapes, weapon hitboxes, and hurtboxes | `--debug-collisions` |
| `--speed <scale>` | Adjusts playback speed (e.g. `0.5` for slow-motion hitbox inspection) | `--speed 0.5` |
| `--time <sec>` | Exact timestamp at which to snap the screenshot (defaults to strike apex) | `--time 0.35` |
| `--cam-angle <angle>`| Studio camera angle: `three_quarters` (default), `front`, `side`, `top_down` | `--cam-angle front` |
| `--cam-dist <float>` | Distance multiplier relative to default studio camera distance (e.g. `2.5` for wide leaps/dashes) | `--cam-dist 2.5` |
| `--cam-height <float>`| Additional elevation offset added to studio camera | `--cam-height 2.0` |
| `--cam-fov <float>` | Camera Field of View in degrees | `--cam-fov 50.0` |
| `--video` | Records full animation to MP4 | `--video` |
| `--duration <sec>` | Custom video duration | `--duration 2.5` |
| `--rig <path>` | Custom base model GLB for raw `.res` animations | `--rig res://.../Enemy_Large.glb` |

---

### C. Combat Scenario Staging (`python capture.py combat`)

Allows agents to set up an arena testbed, spawn combatants, order actions at specific frames, and record or screenshot the resulting interactions to verify game balance, hitbox timing, or ability behaviors.

```bash
python capture.py combat [options]
```

#### CLI Action Syntax
Actions can be scheduled using `--action "<target>:<type>:<param>@<frame>"`.
- **Target**: `player` or `enemy`
- **Type**:
  - `state`: requests StateMachine state (`"enemy:state:EnemyPunch@15"`)
  - `attack`: triggers Player combo strike 1, 2, or 3 (`"player:attack:1@20"`)
  - `damage`: deals direct health damage (`"enemy:damage:25@35"`)
  - `callback`: calls a zero-argument method on the combatant (`"enemy:callback:Taunt@30"`, or `order_callback()` from a scenario script for any node)
  - `screenshot`: saves screenshot at frame (`"screenshot:movies/impact.png@28"`)
- **Enemies**: `--enemy` accepts a registry name (`brute`, `melee`, `ranged`, `firebomber`, `thunder_mage`) or any enemy scene path (`--enemy Enemy/akira_boss.tscn`).
- `--freeze`: holds staged combatants in place with AI and character physics paused; scheduled actions and screenshots still run. Recommended when knockback or drift would spoil a still (frozen actors keep their spawn position, so spawning at rest height is recommended for grounded shots).
- `--verbose`: streams full engine output live instead of the highlight lines. Recommended when debugging custom scenarios (e.g. frame-by-frame trace prints, which are otherwise left out of the summary).

#### Staging & Positioning Options
- `--player-pos <X,Y,Z>`: Custom player spawn position (e.g. `0.0,1.0,4.0`)
- `--enemy-pos <X,Y,Z>`: Custom enemy spawn position (e.g. `0.0,1.0,0.0`)
- `--cam-pos <X,Y,Z>`: Custom studio camera position (e.g. `15.0,5.0,7.5`)
- `--cam-target <X,Y,Z>`: Custom camera look-at target (e.g. `0.0,3.5,7.5`)
- `--cam-fov <float>`: Camera field of view in degrees (e.g. `50.0`)
- `--enable-ai`: Keeps enemy autonomous AI active (disabled by default for scripted choreography)
- `--debug-collisions`: Renders physics colliders and hurtboxes

#### Example CLI Combat Invocations
```bash
# Enemy brute punches player at frame 15, recorded to MP4 video
python capture.py combat --player --enemy brute --action "enemy:state:EnemyPunch@15" --video --duration 2.5

# Player attacks melee enemy, capturing a screenshot at the moment of strike
python capture.py combat --player --enemy melee --action "player:attack:1@10" --action "screenshot:movies/slash_hit.png@22" --frames 30
```

#### Creating Custom Scenario Scripts
You can create a scenario script by extending `CombatScenarioTemplate`.

**Designated Scratch Path:** If you need temporary staging scripts, inspection scripts, or other throwaway scripts, it is recommended to use the gitignored `.scratch/` folder. Scripts kept there are a good fit when the work is exploratory and unlikely to be reused.

When a scenario proves reusable (a standard encounter worth re-running), consider promoting it to `tools/capture/`. `tools/levels/out/` is intended for level-pipeline extraction scripts.

```gdscript
# res://.scratch/my_test_scenario.gd
extends CombatScenarioTemplate

func _setup_scenario() -> void:
    # 1. Spawn combatants
    var player: Character = spawn_player(Vector3(0, 0, 1.8))
    var brute: Character = spawn_enemy("brute", Vector3(0, 0, 0))

    # 2. Schedule actions
    order_state(brute, "EnemyAttack", 15)            # Brute slams at frame 15
    order_screenshot("movies/brute_slam_apex.png", 42) # Capture apex strike
    order_damage(brute, 20.0, 50)                     # Player hits brute during recovery
    order_finish(90)                                  # Finish at frame 90
```

Run your custom script with:
```bash
python capture.py combat --scenario .scratch/my_test_scenario.tscn --video
```

---

### D. Test Suite Recording (`python capture.py test`)

Any existing or future Godot test scene in `test/*.tscn` can be visually recorded as a video. The capturer automatically attaches an arena camera, tracks moving combatants, and turns on collision debug shapes.

```bash
python capture.py test test/test_combo_and_dash_cancel.tscn --duration 5.0
python capture.py test test/test_enemy_brute.tscn --duration 6.0 --gif
```

---

## 3. Architecture & Technical Invariants

### 1. Rendering Server Requirement
Godot's headless mode (`godot --headless`) uses the dummy display server, which does not allocate GPU viewport textures. Therefore:
- Standard test runs (`run_tests.py`) execute headlessly.
- Visual captures (`capture.py`) run with Godot's Forward+/D3D12 display server enabled.
- All commands are invoked through Python with OS watchdog timeouts (25s for screenshots, 90s for video) to guarantee that Godot never hangs the terminal.

### 2. Video Pipeline & FFmpeg
1. Godot's built-in `MovieWriter` records synchronized frames at 60 FPS to an uncompressed `.avi` file via `--write-movie`.
2. Python automatically converts the raw AVI to an H.264 `.mp4` using:
   ```bash
   ffmpeg -y -i <in.avi> -c:v libx264 -pix_fmt yuv420p -preset fast -crf 22 <out.mp4>
   ```
3. The raw AVI is cleaned up automatically, leaving only the compact `.mp4` (and optional `.gif`).

### 3. Strict GDScript Typing
All scripts under `res://tools/capture/` (`map_capturer.gd`, `anim_capturer.gd`, `combat_scenario_template.gd`, `test_capturer.gd`) enforce full static typing (`warnings/untyped_declaration=1`).

---

## 4. Troubleshooting & Visual Diagnostics

### Internal Actor Cameras & Viewport Overrides
Certain character scenes (notably `Player.tscn`) have built-in `Camera3D` nodes (e.g. `CameraRoot/ShakeCamera3D`) initialized with `current = true`. When instantiated into a scene tree, their internal camera can hijack Godot's viewport and cause captures to render black or from unexpected angles.
- **Automatic Suppression**: Both `anim_capturer.gd` and `combat_scenario_template.gd` automatically scan spawned actors, set internal cameras to `current = false`, remove `CameraRoot` nodes, and re-assert the studio camera every physics frame.
- **Custom Scenarios**: When staging custom scenes or actors from scratch, check whether spawned actors contain active `Camera3D` nodes and suppress them so the studio camera remains dominant.

### Choosing Between `anim` and `combat`
- **Solo Abilities / Leaps / Attacks**: Prefer `capture.py anim <scene> --state <StateName> --video`. It runs in an isolated neutral studio with standard lighting. For abilities that cover ground (e.g. `EnemyLeapingDodge`), use `--cam-dist 2.5` to frame the full movement arc.
- **Two-Entity Interactions**: Use `capture.py combat` when testing damage numbers, knockback application, hit reactions, or combo exchanges.

### Moving / Renaming Capturer Files
The capturer scripts own global classes (`MapCapturer`, `CombatScenarioTemplate`, …).
After moving or renaming them, Godot's stale `.godot/global_script_class_cache.cfg`
makes every capture fail with `hides a global script class` (then hang). Regenerate
headless before capturing again:
```bash
godot --headless --path . --editor --quit
```
Headless *game* runs do not rebuild this cache. Never `.gdignore` a folder that
owns global classes — the editor scan must see them.


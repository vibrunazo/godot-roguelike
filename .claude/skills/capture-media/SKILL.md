---
name: capture-media
description: Use when you need a screenshot, contact sheet or video of a level, a character animation, a combat interaction or a running test - to verify a visual change (colors, meshes, VFX, UI, animations) or to show the user something. Covers kit.py capture, this game's anim and combat staging scenes, and the movies/ folder.
---

# Capturing screenshots, contact sheets and video

Outputs land in `movies/` (git-ignored); videos are converted to `.mp4`.
Captures need a display and a GPU renderer: they cannot run headless. `K` below
stands for `python addons/godot_kit/kit.py`.

Pick the cheapest capture that shows what you need:

| You want to see | Use |
|---|---|
| A level's layout | `K capture scene Levels/<level>.tscn [--preset all]` |
| What the game camera shows after N seconds | `K capture scene <scene.tscn> --scene-camera --at N` |
| One character's animation or ability | `K capture scene tools/capture/anim_stage.tscn --scene-camera --at 0.5 -- --target=<scene> --state=<StateName>` |
| A whole attack or ability as one picture | the same with `--sheet 6 --duration <seconds>` |
| Two or more characters interacting (hits, reactions, combos) | `K capture scene tools/capture/combat_stage.tscn --scene-camera --video --duration 3 -- --player --enemy=<name or scene> --action=enemy:state:<State>@<frame>` |
| A video of any of these | add `--video --duration <seconds>` |
| A test suite as it runs | `K capture test test/test_<name>.tscn` |

Everything before `--` is the kit's (`--at`, `--sheet`, `--duration`,
`--video`, `--output`, `--full-res`, `--debug-collisions`, `--show-ui`,
`--verbose`); everything after it goes to the staging scene. Name the file
with `--output movies/<name>.png` (or `.mp4`): by default a stage's captures
are all called `anim_stage_scene.*` or `combat_stage_scene.*`.

**Screenshots are 768 px wide by default to save tokens**: a full-size frame
costs over twice as much to look at. The frame is rendered at the game's full
resolution and only shrunk when saved, so framing and UI layout are what
players see. **If small details are hard to see (thin VFX, particles, small UI
text, one-pixel artifacts), capture again with `--full-res`.**

**Checking a motion yourself** (an attack, a leap, a hit reaction), cheapest
first:
- **Contact sheet:** `--sheet N` spreads N frames over `--duration` game
  seconds and tiles them into one image, for less than one full-size
  screenshot. Set `--duration` to the animation's length to see wind-up,
  strike and recovery at once.
- **The video itself**, if you can take video input.
- **Frames from a video** otherwise: `ffmpeg -i movies/<name>.mp4 -vf "fps=4,scale=256:-1,tile=3x2" .scratch/frames/f_%02d.png`
  tiles 6 frames per 768 px image. Keep them in `.scratch/` and delete them
  when done.

## The animation stage (`tools/capture/anim_stage.tscn`)

A lit studio floor, a camera and one target: a character scene (`.tscn`), an
animation resource (`.res`, mounted on a base rig) or a source `.glb`. Its
arguments, after `--`:

| Argument | Effect |
|---|---|
| `--target=<path>` | what to stage (`Enemy/enemy_brute.tscn`, `Assets/.../Melee_2H_Attack_Chop.res`) |
| `--state=<name>` | request a body state on a character (`EnemyPunch`, `EnemyAttack`) |
| `--anim=<name>` | play an animation directly on its `AnimationPlayer` (AnimationTree off) |
| `--dummy` | a frozen target dummy at strike distance |
| `--speed=<scale>` | playback speed (`0.5` for slow motion) |
| `--cam-angle=<a>` | `three_quarters` (default), `front`, `side`, `top_down` |
| `--cam-dist=<x>`, `--cam-height=<m>`, `--cam-fov=<deg>` | studio camera; `--cam-dist=2.5` frames dashes and leaps |
| `--rig=<glb>` | base rig for a `.res` animation |

A state needs a few frames to start: shoot with `--at 0.4` or later.

## The combat stage (`tools/capture/combat_stage.tscn`)

An arena floor, a camera that frames the combatants, and actions on exact
physics frames. Its arguments, after `--`:

- `--player`, `--enemy=<name or scene>`: a registry name (`brute`, `melee`,
  `ranged`, `firebomber`, `thunder_mage`, `headless_daemon`,
  `backface_knight`) or any enemy scene (`--enemy=Enemy/akira_boss.tscn`).
- `--action=<target>:<type>:<param>@<frame>` (repeatable), target `player` or
  `enemy`: `state` requests a body state (`enemy:state:EnemyPunch@15`),
  `attack` a player combo strike 1-3 (`player:attack:1@20`), `damage` a hit
  through the `Hurtbox` like a real attack (`enemy:damage:25@35`), `callback`
  a zero-argument method (`enemy:callback:Taunt@30`). `screenshot:<path>@<frame>`
  saves an extra named screenshot at that frame.
- `--freeze` holds the combatants in place (AI and physics paused; actions and
  screenshots still run). `--enable-ai` keeps enemy AI on (off by default).
- `--player-pos=`, `--enemy-pos=`, `--cam-pos=`, `--cam-target=` (`X,Y,Z`) and
  `--cam-fov=` place the actors and the camera.

The kit ends the run (`--at` for a screenshot, `--duration` for a video or
sheet): make it long enough for the last action. At 60 fps, frame N is N/60 s.

A scripted scenario extends `CombatStage` and overrides `_setup_scenario()`
with `spawn_player()`, `spawn_enemy()`, `order_state()`, `order_damage()`,
`order_callback()` and `order_screenshot()`. Saved scenarios in
`tools/capture/scenarios/` say in their docstring how to run them.

## Framing and clutter

- Actor scenes (the player) bring their own cameras; both stages suppress
  them and re-assert their camera every physics frame. A staging scene of
  your own must do the same, or the capture renders from the wrong camera.
- In `capture scene` without `--scene-camera`: `--target-node <Name>` frames
  one node; `--cam-pos X,Y,Z --cam-target X,Y,Z` places the camera yourself;
  `--freeze` stops the scene's processing.
- The HUD and the level title overlay are in the `capture_hidden` group and
  `SceneTransition` is in `capture.hide_paths` (`godot_kit.toml`): all hidden
  unless `--show-ui`. The combat stage also hides health bars then.
- The automatic framing covers visible meshes and GridMap cells; huge props
  leave it through the `capture_bounds_ignore` group (the level template's
  `Pit` void plane is in it).

## Rules

- Visual changes are verified this way, never with suite tests.
- Throwaway staging scenes and scripts go in `.scratch/`; promote a scenario to
  `tools/capture/scenarios/` only when it is worth re-running.
- A new staging scene reads its arguments after `--scene-args` in
  `OS.get_cmdline_user_args()`, builds its actors and current camera, and
  never saves the main capture or quits: the kit does both.

---
name: capture-media
description: Use when you need a screenshot, contact sheet or video of a scene or a running test - to verify a visual change (colors, meshes, VFX, UI, motion) or to show the user something. Covers kit.py capture and the {{OUTPUT_DIR}}/ folder.
---

# Capturing screenshots, contact sheets and video

Outputs land in `{{OUTPUT_DIR}}/` (git-ignored); videos are converted to
`.mp4`. Captures need a display and a GPU renderer: they cannot run headless.

Pick the cheapest capture that shows what you need:

| You want to see | Use |
|---|---|
| A scene's layout | `python {{KIT}}/kit.py capture scene <scene.tscn> [--preset all]` |
| What the game camera shows after N seconds | `python {{KIT}}/kit.py capture scene <scene.tscn> --scene-camera --at N` |
| A motion as one picture | `python {{KIT}}/kit.py capture scene <scene.tscn> --scene-camera --sheet 6 --duration 3` |
| A video | `python {{KIT}}/kit.py capture scene <scene.tscn> --video --duration 4` |
| A test suite as it runs | `python {{KIT}}/kit.py capture test {{TEST_DIR}}/test_<name>.tscn` |

**Screenshots are 768 px wide by default to save tokens**: a full-size frame
costs over twice as much to look at. The frame is rendered at the game's full
resolution and only shrunk when saved, so framing and UI layout are what
players see. **If small details are hard to see (thin VFX, particles, small UI
text), capture again with `--full-res`.**

**Checking a motion yourself**, cheapest first:
- **Contact sheet:** `--sheet N` spreads N frames over `--duration` game
  seconds and tiles them into one image, for less than one full-size
  screenshot.
- **The video itself**, if you can take video input.
- **Frames from a video** otherwise: `ffmpeg -i {{OUTPUT_DIR}}/<name>.mp4 -vf "fps=4,scale=256:-1,tile=3x2" .scratch/frames/f_%02d.png`
  tiles 6 frames per 768 px image. Keep them in `.scratch/` and delete them
  when done.

Framing and clutter:
- `--target-node <Name>` frames one node; `--cam-pos X,Y,Z --cam-target X,Y,Z`
  places the camera yourself; `--freeze` stops the scene's processing.
- HUDs and fades are hidden through `capture.hide_paths` in `godot_kit.toml`
  or the `capture_hidden` group (`--show-ui` keeps them). The automatic
  framing covers visible meshes and GridMap cells; huge props such as a ground
  plane leave it through the `capture_bounds_ignore` group.

Rules:
- Visual changes are verified this way, never with suite tests.
- Throwaway staging scenes and scripts go in `.scratch/`.

---
name: capture-media
description: Use when you need a screenshot or video of a level, a character animation, a combat interaction or a running test - to verify a visual change (colors, meshes, VFX, UI, animations) or to show the user something. Covers capture.py and the movies/ folder.
---

# Capturing screenshots and video

**Full reference: `CAPTURE.md`** (every subcommand, option, preset, how
scenarios are scripted, and the rendering and camera caveats). Outputs land in
`movies/` (git-ignored); videos are converted to `.mp4`.

Pick the simplest tool that shows what you need:

| You want to see | Use |
|---|---|
| A level's layout | `python capture.py map Levels/<level>.tscn [--preset all]` |
| One character's animation or ability | `python capture.py anim <scene> --state <StateName> --video` (add `--cam-dist 2.5` for dashes and leaps) |
| Two or more characters interacting (hits, reactions, combos) | `python capture.py combat --player --enemy <name or scene> --action "enemy:state:<State>@<frame>" --video` |
| A test suite as it runs | `python capture.py test test/test_<name>.tscn` |
| A whole attack or ability as one picture | `python capture.py anim <scene> --state <StateName> --sheet 6` |

**Screenshots are low resolution by default (768 px wide) to save tokens**:
a full-size frame costs over twice as much to look at. The frame is rendered
at the game's full resolution and only shrunk when saved, so framing and UI
layout are what players see. **If you have trouble seeing small patterns or
details (thin VFX, particles, small UI text, one-pixel artifacts), capture
again with `--full-res`.**

**Checking a motion yourself** (an attack, a leap, a hit reaction), cheapest
first:
- **Contact sheet:** `--sheet N` spreads N frames over the animation (or
  `--duration`) and tiles them into one image. It costs less than one
  full-size screenshot and shows wind-up, strike and recovery at once.
- **The video itself**, if you can take video input (some multimodal models
  can read `.mp4` directly). Record with `--video`.
- **Frames from a video**, if you cannot take video input: ffmpeg is
  installed. `ffmpeg -i movies/<name>.mp4 -vf "fps=4,scale=768:-1"
  .scratch/frames/f_%02d.png` extracts 4 frames per second at the default
  screenshot width. For sheets instead, shrink each frame to a third and
  tile them: `-vf "fps=4,scale=256:-1,tile=3x2"` gives 768 px wide images of
  6 frames. Keep them in `.scratch/` and delete them when done.

- Visual changes are verified this way, never with suite tests.
- Throwaway staging scenes and scripts go in `.scratch/`; promote a scenario to
  `tools/capture/` only when it is worth re-running.
- Captures need a real display server and GPU renderer; `capture.py` handles
  the launch and its own watchdog timeouts.

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

- Visual changes are verified this way, never with suite tests.
- Throwaway staging scenes and scripts go in `.scratch/`; promote a scenario to
  `tools/capture/` only when it is worth re-running.
- Captures need a real display server and GPU renderer; `capture.py` handles
  the launch and its own watchdog timeouts.

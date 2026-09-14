# tools/levels — Level Building Pipeline

CLI pipeline for designing, assembling, validating, and baking combat levels.
Level 4 (`Levels/level_4.tscn`, a 2× mirror of Level 2) was built end-to-end
with these tools; every step below reproduces its artifacts byte-for-byte
(see "Worked example").

All `.gd` tools run headless through the project runner, which forwards extra
args to the script (`OS.get_cmdline_user_args()`):

```bash
python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn
```

> Godot-side file arguments must be `res://` (or project-relative) paths.
> Absolute OS paths (`/tmp/...`) do **not** work with `FileAccess` — the tools
> reject them loudly. Pure-Python steps accept any OS path. Generated
> intermediates go to `tools/levels/out/` (git-ignored and `.gdignore`d).

## Tool inventory

| Tool | Purpose |
| :--- | :--- |
| `dump_cells.gd` | Dumps a level's Floormap/Wallmap cells to text (`--level= --out=`). Starting point for editing any existing level. |
| `validate_layout.py` | Design-time checks on cell files: floor connectivity (BFS), pit-quad coverage, wall sanity, VoxelGI suggestion. No engine needed. |
| `generate_navmesh.py` | Builds a `NavigationMesh` snippet (shared-corner lattice) from floor cells. **Scaffold only** — the real bake happens in the editor (tip 1). |
| `pack_cells.gd` | Serializes cell files through the engine into a temp scene. GridMap `data` arrays use an internal packed encoding: never hand-write them. |
| `assemble_level.py` | Builds an inherited level `.tscn` from a JSON spec (template + cells + pits + exit + hazards + litter + VoxelGI). Recomputes root `index` attributes automatically. |
| `bake_level_gi.gd` / `.tscn` | Nav pre-check + VoxelGI bake (`--level= --gi-out=`). Must run **with** the display server (see command below). |
| `examples/double_level.py` | Worked example: the Level 4 mirror recipe. Reads a dump, writes cells + navmesh + spec. Copy and adapt for new designs. |

The gate for every level is the committed test `test/test_level_rotation_nav.tscn`:
it loads each `SceneTransition.levels` entry and checks core nodes, baked
VoxelGI data, navmesh/GI footprint coverage, and a spawn→exit nav path.

## End-to-end: designing a new level

```bash
# 1. Dump the level you are riffing on
python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn --out=tools/levels/out/l2.txt

# 2. Design: write your own step-2 script (see examples/double_level.py),
#    producing floor.txt / wall.txt cell files
python tools/levels/examples/double_level.py --cells tools/levels/out/l2.txt --out-dir tools/levels/out/l4proof

# 3. Validate the layout BEFORE touching the engine (fast iteration here)
python tools/levels/validate_layout.py --floor tools/levels/out/l4proof/floor.txt \
    --wall tools/levels/out/l4proof/wall.txt --pits "0,-8;-4,-20" --start 0,0 --goal -3,-17

# 4. Pack cells through the engine, then assemble the scene from your spec JSON
python run_scratch.py tools/levels/pack_cells.gd -- --floor=tools/levels/out/l4proof/floor.txt \
    --wall=tools/levels/out/l4proof/wall.txt --out=tools/levels/out/l4proof/packed_cells.tscn
python tools/levels/assemble_level.py --spec tools/levels/out/l4proof/spec.json --out Levels/level_5.tscn

# 5. BAKE THE NAVMESH IN THE EDITOR (NavigationRegion3D > Bake). Non-negotiable (tip 1).

# 6. Bake VoxelGI with the display server + hard watchdog (edit paths first)
python -c "
import shutil, subprocess
godot = shutil.which('godot') or 'godot'
cmd = [godot, '--path', '.', 'tools/levels/bake_level_gi.tscn', '--',
       '--level=Levels/level_5.tscn', '--gi-out=Levels/GlobalIlluminationData/level_5_voxel_gi_data.res']
subprocess.run(cmd, shell=False, timeout=280)
"

# 7. Reference the baked .res from the level (assembler does this when
#    "gi_data" is set in the spec), register the level in
#    SceneTransition.levels, then verify:
python run_tests.py test/test_level_rotation_nav.tscn
python capture.py map Levels/level_5.tscn --preset all
```

## Spec format (`assemble_level.py`)

```json
{
  "template": "Levels/level_2.tscn",
  "root_name": "Level5",
  "uid": null,
  "packed_cells": "tools/levels/out/l5/packed_cells.tscn",
  "navmesh_snippet": "tools/levels/out/l5/navmesh.txt",
  "navmesh_id": "NavigationMesh_level5",
  "pit_pattern_from": "Pit2",
  "extra_pits": [{"name": "Pit3", "x": -8, "z": -20}],
  "exit": [-12, 0, -68],
  "hazard_pattern_from": "SpikesHazard2",
  "extra_hazards": [{"name": "SpikesHazard3", "ext_id": "5_spikes", "x": 5, "z": -59}],
  "litter_copies": [{"name": "Couch2N", "from": "Couch2", "dx": 0, "dz": -40}],
  "player": null,
  "voxelgi": {"pos": [-4, 0, -32], "size": [32, 20, 88]},
  "gi_data": "res://Levels/GlobalIlluminationData/level_5_voxel_gi_data.res",
  "gi_ext_id": "4_level5",
  "out": "Levels/level_5.tscn",
  "seed": 20260914
}
```

- `template` should be a level with a pit-quad pattern (`Pit2`) and a hazard
  pattern to clone; Level 2 or 3 both qualify.
- `uid: null` generates a fresh scene uid; pin one to reproduce a file exactly.
- `player: null` keeps the template spawn; otherwise `[x, y, z]`.
- `gi_data: null` assembles the pre-bake state (no data reference — required,
  because the `.res` does not exist yet; see tip 3). Set it after baking.
- `ext_id` values are the `ExtResource` ids in the template file (e.g.
  `"5_spikes"`); find them at the top of the template `.tscn`.

## Tips learned building Level 4

1. **The navmesh must be baked in the editor. Period.** A hand-generated
   polygon lattice can be fully walkable (ours passed path queries) and still
   not be a bake: no agent-radius erosion around walls/pits, no recast
   partitioning. The committed rotation test guards the *outcome* either way,
   but ship only editor-baked meshes. (`generate_navmesh.py` output is a
   scaffold that unblocks assembly/testing before the bake.)
2. **Never hand-write GridMap `data` arrays.** The `PackedInt32Array` encoding
   is engine-internal (3 ints/cell, position-packed). Always round-trip through
   `pack_cells.gd` — it is byte-deterministic across runs (proven by diff).
3. **`ext_resource` must point at an existing file.** A level referencing a
   not-yet-baked `.res` fails to *parse* (engine error at load, then a hang).
   Assemble with `gi_data: null` first, bake, then set the reference.
4. **Navmesh id and reference are a pair.** Replacing the `NavigationMesh`
   sub-resource without updating `navigation_mesh = SubResource(...)` (or vice
   versa) loads a level with the wrong/empty mesh and nothing errors visibly.
   The assembler updates both; the rotation test catches a mismatch via the
   coverage check.
5. **Root `index` attributes are positional.** Inserting pit/hazard nodes shifts
   every later sibling (`VoxelGI`, `ExitPoint`, …). The assembler recomputes
   them from the merged child order — if you hand-edit, recount.
6. **The nav map needs frames to sync.** After instancing a level, poll
   `map_get_closest_point` until the spawn snaps (cap ~120 physics frames)
   instead of waiting a fixed 2 frames — fixed waits give order-dependent
   false passes/failures when checking several levels in one scene.
7. **GDScript coroutines need `await` at the call site.** Any function
   containing `await` must be called with `await` (`if not await _verify…`).
   This bit twice; the failure mode is a parse error followed by a hang.
8. **`quit()` does not stop the current frame.** After `quit(1)` on an error
   path, `return` immediately or the rest of `_init` still executes.
9. **After moving/renaming `class_name` scripts, rescan.** A stale
   `.godot/global_script_class_cache.cfg` produces `hides a global script
   class` parse errors (then hangs). Regenerate headless with
   `godot --headless --path . --editor --quit` — never hand-edit the cache,
   and never `.gdignore` a folder that owns global classes (it would hide them
   from the scan). Headless *game* runs do not rebuild it.
10. **Validate before you assemble, capture after.** `validate_layout.py`
    catches disconnected tiles, uncovered pits, and floating walls in
    milliseconds — including one real wart it found in Level 4 (two wall
    segments over the notch void, since removed). Then capture isometric +
    top-down + a low close-up of any new edge: top-down lies about floating
    walls, low angles do not.
11. **Pit quads cover interior gaps; notches stay open.** Gaps connected to the
    outer void are boundary notches and need no quad (Level 2 leaves its notch
    unwalled — follow that precedent rather than bridging voids with walls).
12. **Size VoxelGI with margin and keep dynamics out of the bake.**
    `validate_layout.py` prints a suggested center/size (footprint + 4 m).
    Characters/weapons/props must have `gi_mode = 0` or they bake permanent
    shadow artifacts into the GI data.

## Future tool ideas (not yet built)

- **`new_level.py` scaffolder**: mint an empty inherited level (template nodes,
  empty GridMaps, placeholder navmesh/GI, spawn + exit) from a name + bounds,
  so new levels start assemblable instead of hand-copied.
- **Dressing validator**: check each `Litter` prop and hazard sits on (not
  beside) a floor tile — the one placement class `validate_layout.py` does
  not cover yet.
- **Contact-sheet capture**: one command producing iso/top/side + a low orbit
  video for a level, for quick visual review without hand-posing cameras.
- **Playthrough smoke test**: extend the rotation test to walk the player
  spawn→exit via the nav path and assert no falls/stalls, catching
  wall-gap escapes the static checks cannot see.


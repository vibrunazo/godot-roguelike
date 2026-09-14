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
| `validate_layout.py` | Design-time checks on cell files: floor connectivity (BFS), wall sanity, no wall overlaps, dressing-on-floor (`--dressing`), VoxelGI suggestion. No engine needed. (Pit-quad coverage is retired: the template abyss bottoms every hole.) |
| `generate_walls.py` | Perimeter walls from floor cells (outer-void sides only, per-side orientations, optional windows) plus `pit_lining()`: shaft walls ringing interior holes, copied from shipped Level 2. Interior pillars stay hand-designed. |
| `generate_navmesh.py` | Builds a `NavigationMesh` snippet (shared-corner lattice) from floor cells. **Scaffold only** — ship only real bakes (tip 1). |
| `pack_cells.gd` | Serializes cell files through the engine into a temp scene. GridMap `data` arrays use an internal packed encoding, so hand-writing them tends to corrupt the scene — round-trip through this tool instead. |
| `assemble_level.py` | Builds an inherited level `.tscn` from a JSON spec (template + cells + exit + hazards + litter + VoxelGI). Supports `strip_*` dressing removal, `litter_placed`, hazard kinds, `hide_nodes` (pins `visible = false` on inherited nodes; never use on `Pit` — the template abyss must stay visible). `extra_pits` is honored for legacy specs only. Recomputes root `index` attributes automatically. |
| `bake_navmesh.gd` | Headless navmesh bake via `NavigationMeshGenerator` (`--level= --out=`). Output proved byte-equivalent (modulo float formatting) to the editor's Bake button on Level 4. |
| `bake_level_gi.gd` / `.tscn` | Nav pre-check + VoxelGI bake (`--level= --gi-out=`). Must run **with** the display server (see command below). |
| `examples/double_level.py` | Worked example: the Level 4 mirror recipe. Reads a dump, writes cells + navmesh + spec. Copy and adapt for new designs. |
| `examples/grand_hall.py` | Worked example: the original Level 5 design (vestibule + hall + pit lakes + colonnades). Shows perimeter generation, floor art variants, explicit dressing. |
| `examples/two_rooms.py` | Worked example: the Level 6 design (two rooms + railed bridge, no per-level pit quads). Composes `layout.py` primitives (`room`/`bridge`/`compose`), the pattern to copy for future multi-part levels. |
| `examples/four_rooms.py` | Worked example: the Level 7 design (four-room ring with 1-tile dash-jump gaps, 1-wide outer bridges, spike-gauntlet bridge, tall stub segments on gap fronts). Shows `bridge(sides=...)` for single-row spans and stub-aware gap-band jump assertions. |
| `examples/three_islands.py` | Worked example: the Level 8 design (three islands joined by tall-railed causeways, lined central pit lake). First shipped use of `corridor()`; shows `room(holes=)` + `pit_lining()` for lakes. |
| `examples/crossing.py` | Worked example: the Level 9 design (two rooms joined by a long open bridge over an unjumpable void). First shipped use of `bridge(rails="open")`; shows auto long-side rails on multi-row spans and an open room cliff (`edge={"e": None}`). |
| `examples/crucible.py` | Worked example: the Level 10 design (symmetric 11x11 finale arena, all rims low cliffs, four lined 1x2 pit lakes, lone center pillar). Shows all-low `edge` dicts, `room(holes=)` with multiple lakes, and `check_cover_clearances` (lone cover keeps 3 m+ off pit edges so no thin navmesh sliver wedges enemies). |
| `layout.py` | Composable floor-plan primitives: `room()` (solid block, optional holes and per-side tiers), `bridge()` (railed strip: `low`/`open`/`tall`, optional explicit `sides`), `corridor()` (tall-railed bridge), `touches()`/`compose()` junction checks, `paint()` floor-art variants. Edge letters are the generator's (`n`=min-z, `s`=max-z, `w`=min-x, `e`=max-x). Overrides apply only where derivation would already emit a wall, so part junctions (bridge mouths) stay wall-free automatically. |

The gate for every level is the committed test `test/test_level_rotation_nav.tscn`:
it loads each `SceneTransition.levels` entry and checks core nodes, baked
VoxelGI data, navmesh/GI footprint coverage, a spawn→exit nav path, pit
shaft-wall lining, abyss-plane presence (the template `Pit` must be visible
and giant — per-level pit quads are obsolete), and navmesh bake authenticity
(recast erosion around walls normally leaves fractional-coordinate verts, so
an all-integer x/z lattice is treated as an unbaked scaffold and fails).

## End-to-end: designing a new level

```bash
# 1. Dump the level you are riffing on
python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn --out=tools/levels/out/l2.txt

# 2. Design: write your own step-2 script (see examples/double_level.py),
#    producing floor.txt / wall.txt cell files
python tools/levels/examples/double_level.py --cells tools/levels/out/l2.txt --out-dir tools/levels/out/l4proof

# 3. Validate the layout BEFORE touching the engine (fast iteration here)
python tools/levels/validate_layout.py --floor tools/levels/out/l4proof/floor.txt \
    --wall tools/levels/out/l4proof/wall.txt --start 0,0 --goal -3,-17

# 4. Pack cells through the engine, then assemble the scene from your spec JSON
python run_scratch.py tools/levels/pack_cells.gd -- --floor=tools/levels/out/l4proof/floor.txt \
    --wall=tools/levels/out/l4proof/wall.txt --out=tools/levels/out/l4proof/packed_cells.tscn
python tools/levels/assemble_level.py --spec tools/levels/out/l4proof/spec.json --out Levels/level_5.tscn

# 5. Bake the navmesh headlessly, splice it into the level (tip 1)
python run_scratch.py tools/levels/bake_navmesh.gd -- --level=Levels/level_5.tscn \
    --out=tools/levels/out/l5proof/navmesh_baked.txt
# then replace the scaffold NavigationMesh block in Levels/level_5.tscn with the
# baked snippet (Level 5's proof run did this with a small splice script).
# Caution: re-running the design script (step 2) rewrites spec.json with the
# scaffold snippet and gi_data null, so a re-assemble after that silently
# ships the scaffold and drops the GI reference. After any redesign, repeat
# the spec patch (baked snippet + gi_data path) before the final assemble —
# the rotation test fails on scaffold meshes, which is how this was caught.

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
  "strip_pits": true,
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

- `template` should be a level with the hazard/litter patterns to clone;
  Level 2 or 3 both qualify.
- The template's `Pit` is a giant abyss plane bottoming every hole and cliff
  edge — per-level pit quads are obsolete, so new specs simply omit
  `extra_pits` (still honored for legacy specs) and `strip_pits` is a
  harmless no-op once the base has no `Pit*` blocks left.
- `hide_nodes` pins `visible = false` on inherited root nodes the layout
  must not show. Never use it on `Pit`: hiding the abyss breaks the level
  (the rotation test fails a hidden or undersized `Pit`).
- `uid: null` generates a fresh scene uid; pin one to reproduce a file exactly.
- `player: null` keeps the template spawn; otherwise `[x, y, z]`.
- `gi_data: null` assembles the pre-bake state (no data reference — required,
  because the `.res` does not exist yet; see tip 3). Set it after baking.
- `ext_id` values are the `ExtResource` ids in the template file (e.g.
  `"5_spikes"`); find them at the top of the template `.tscn`.

## Tips learned building Level 4

1. **Ship real bakes rather than hand-made meshes.** A hand-generated
   polygon lattice can be fully walkable (ours passed path queries) and still
   not be a bake: no agent-radius erosion around walls/pits, no recast
   partitioning, no obstacle carving. (`generate_navmesh.py` output is only
   a scaffold that unblocks assembly/testing before the bake.)
   **Prefer the two-step bake API headlessly over one-step `bake()`.**
   `bake_navmesh.gd` parses with `parse_source_geometry_data()` (which
   exposes `has_data()`) then `bake_from_source_geometry_data()` — verified
   working headlessly (Level 5: 115 polys with wall erosion and cleared
   props). In our checks the one-step `bake()` returned an *empty* mesh in
   `-s` runs (including a fresh-mesh control on shipped Level 2), so the
   script refuses empty/unchanged results loudly rather than passing the
   scaffold off as baked. The rotation test additionally trips on
   integer-lattice meshes (below).
2. **Avoid hand-writing GridMap `data` arrays.** The `PackedInt32Array` encoding
   is engine-internal (3 ints/cell, position-packed); round-tripping through
   `pack_cells.gd` is the reliable path — it is byte-deterministic across runs
   (proven by diff).
3. **`ext_resource` must point at an existing file.** A level referencing a
   not-yet-baked `.res` fails to *parse* (engine error at load, then a hang).
   Assemble with `gi_data: null` first, bake, then set the reference.
4. **Navmesh id and reference are a pair.** Replacing the `NavigationMesh`
   sub-resource without updating `navigation_mesh = SubResource(...)` (or vice
   versa) loads a level with the wrong/empty mesh and nothing errors visibly.
   The assembler updates both; the rotation test catches a mismatch via the
   coverage check.
5. **Root `index` attributes are positional.** Inserting hazard/litter nodes shifts
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
   `godot --headless --path . --editor --quit` — hand-editing the cache tends
   to corrupt it, and `.gdignore`ing a folder that owns global classes hides
   them from the scan. Headless *game* runs do not rebuild it.
10. **Validate before you assemble, capture after.** `validate_layout.py`
    catches disconnected tiles, uncovered pits, and floating walls in
    milliseconds — including one real wart it found in Level 4 (two wall
    segments over the notch void, since removed). Then capture isometric +
    top-down + a low close-up of any new edge: top-down lies about floating
    walls, low angles do not.
11. **No per-level pit quads; the template abyss bottoms everything.** The
    template's giant unshaded `Pit` plane covers every interior hole and
    cliff edge, so specs never add quads and `validate_layout.py` no longer
    checks coverage. Gaps connected to the outer void are boundary notches
    (Level 2 leaves its notch unwalled — follow that precedent rather than
    bridging voids with walls).
12. **Every pit still needs a shaft-wall ring.** A hole over the abyss with
   bare tile sides reads unfinished. Shipped levels ring each interior hole
   with `y=-1` shaft walls whose inner faces drop from the rim toward the
   abyss at `y=-2` (see `pit_lining()` in `generate_walls.py`: cells on
   every other slot along each hole edge, straddling the hole/floor
   boundary — possible because each 4 m-wide wall mesh spans two 2 m grid
   cells). The committed rotation test enforces this: every hole-tile side
   facing floor must touch a `y=-1` wall cell.
13. **Never write `#` comments in `.tscn` files.** The scene text format is
    INI-style: only `;` starts a comment. A `#` line parses without a load
    error but silently swallows the node block that follows it (we lost the
    template's entire abyss plane this way — the rotation test's abyss check
    is what caught it). Keep `.tscn` hand-edits comment-free.
14. **Size VoxelGI with margin and keep dynamics out of the bake.**
    `validate_layout.py` prints a suggested center/size (footprint + 4 m).
    Characters/weapons/props must have `gi_mode = 0` or they bake permanent
    shadow artifacts into the GI data.

## Wall geometry and tiling (read before emitting wall cells)

Wall cells are 2 m, but each wall mesh is 4 m wide and centered on its
cell's grid point (`wall_map.tres` AABB `x -2..2`), so one mesh covers two
cells. An X-running wall at cell `(wx, wz)` spans world `x wx*2-2..wx*2+2`
and only `z wz*2±0.5`; Z-running walls (orient 16/22) are transposed.

Cells placed on every slot of a straight run therefore overlap their
neighbours by 2 m of coplanar faces, which shimmers in game. Shipped runs
avoid this by occupying every other slot so panels tile edge-to-edge: an
8 m edge at world `x -12..-4` takes cells `wx=-5` and `wx=-3` (spans
`-12..-8`, `-8..-4`). `generate_walls.generate()` and `pit_lining()` both
encode this spacing; hand-placed runs (pillars, dividers) need the same
treatment. Perpendicular crossings read as normal corners and stacked
tiers share no visible faces, so only same-axis, same-tier overlap counts
— which is exactly what `validate_layout.check_no_wall_overlap()` tests.
Run it on every new wall file, and confirm runs visually with a low
grazing-angle capture along the wall (top-down views hide the shimmer).

## Wall orientation rule (read before placing walls by hand)

GridMap orientation decides which way a wall piece runs. Shipped-Level-2
conventions, all verified visually on Levels 4–5:

- Pieces running along **X**: orient **10** (north-ring style).
- Pieces running along **Z** on the **west** side: orient **16**.
- Pieces running along **Z** on the **east** side: orient **22**.
- Pit-lining orients differ from perimeter ones: hole **north** edges use
  orient **0**, south **10**, west **16**, east **22** (the lining mesh hugs
  the opposite face of the boundary plane). `pit_lining()` encodes this —
  prefer it over hand-placing rings.
- A single row of cross-oriented pieces reads as fins/comb teeth, **not** a
  divider — Level 2 builds X-running dividers as *double rows* of Z-pieces.
- Shipped solid walls carry no windows; windows appear only in `y=0` walls.
  `generate_walls.py` encodes all of this.

## Wall height tiers (read before placing walls at any y)

Raycast-measured on shipped levels (floor top ~0.0): a `y=-1` wall spans
`y -4..0` and tops out flush with the floor, so it reads as a rim or floor
inlay. Full-height architecture (tops ~4.1) lives at `y=0`. Shipped Level 2
mixes both — tall `y=0` west/south perimeters, low `y=-1` north/east rims,
`y=-1` pit lining throughout — while Level 1 is rims only.
A past Level 5 design emitted freestanding colonnades at `y=-1` and they
rendered as invisible floor decoration; the rotation test now fails any
`y=-1` cell fully covered by solid floor (rings no edge). Top-down and
isometric captures hide tier mistakes — checking new architecture calls for
a low, near-walk-height camera angle.

## Floor art without hand-painting

Level 2's blue/grey mix follows no parity rule (checked), so
`examples/grand_hall.py` assigns variants from Level 2's measured
distribution (`(0,10):17, (1,10):15, (1,0):8, (0,0):6`) by stable per-tile
hash. Position-stable regardless of iteration order, reads as shipped.

## Future tool ideas (not yet built)

- **`new_level.py` scaffolder**: mint an empty inherited level (template nodes,
  empty GridMaps, placeholder navmesh/GI, spawn + exit) from a name + bounds,
  so new levels start assemblable instead of hand-copied.
- **Navmesh splice tool**: fold the baked-snippet splice (currently an inline
  proof script) into a maintained `splice_navmesh.py`, and likewise a
  `set_gi_data.py` for the post-bake GI reference.
- **Contact-sheet capture**: one command producing iso/top/side + a low orbit
  video for a level, for quick visual review without hand-posing cameras.
- **Playthrough smoke test**: extend the rotation test to walk the player
  spawn→exit via the nav path and assert no falls/stalls, catching
  wall-gap escapes the static checks cannot see.


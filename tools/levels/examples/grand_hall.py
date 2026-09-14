#!/usr/bin/env python3
"""Worked example #2: a grand-hall level (Level 5), designed from scratch.

Unlike the mirrored Level 4, this layout is original: a wide entrance
vestibule opens into a large hall with two offset pit lakes, freestanding
pillar colonnades, partial cross-walls, and explicitly dressed hazards/props.
At ~150 floor tiles it is substantially bigger than Level 4 (92).

Pipeline (mirrors the README):
    python tools/levels/examples/grand_hall.py --out-dir tools/levels/out/l5proof
    python tools/levels/validate_layout.py --floor ... --wall ... --dressing ...
    pack -> assemble (spec.json) -> bake navmesh -> splice -> bake GI -> register

Pit lakes need no quads: the template's giant abyss plane bottoms every hole.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from generate_navmesh import generate, render_snippet  # noqa: E402
from generate_walls import generate as gen_walls  # noqa: E402
from generate_walls import pit_lining  # noqa: E402
from validate_layout import check_connectivity, check_dressing  # noqa: E402
from validate_layout import check_no_wall_overlap  # noqa: E402
from validate_layout import check_walls_touch_floor  # noqa: E402
from validate_layout import load_cells  # noqa: E402

# --- footprint (floor grid cells, y=0; tiles are 4m) ---
VESTIBULE_X = (-1, 0)
VESTIBULE_Z = (0, 1, 2)
HALL_X = (-4, -3, -2, -1, 0, 1, 2, 3)
HALL_Z = tuple(range(-18, 0))

# Interior holes (removed from the floor; lined with shaft walls, bottomed by
# the template's giant abyss plane — no per-level quads needed).
LAKE_A = [(x, z) for x in (-3, -2) for z in (-13, -12, -11)]
LAKE_B = [(x, z) for x in (1, 2) for z in (-8, -7, -6)]

# Freestanding interior walls: (x, y, z, item, orient). These stand TALL at
# y=0; y=-1 would bury them flush with the floor (verified by raycast
# heightmap: floor top ~0.0, y=-1 tops ~0.0, y=0 tops ~4.1).
# Cells tile the run every OTHER slot (4m meshes on a 2m grid): consecutive
# cells overlap coplanar faces and shimmer. Spans below cover the intended
# extents exactly (west colonnade z -32..-24, east z -12..-4, north cross x
# -8..4, south segments with the central gap kept open).
# Orientation rule (learned the hard way): pieces running along X use orient
# 10 (north-ring style), pieces running along Z use 16/22. A single row of
# Z-pieces reads as fins, not a divider. All solid: shipped solid walls carry
# no windows.
PILLARS = [
    (-6, 0, -15, 0, 16), (-6, 0, -13, 0, 16),  # west colonnade
    (2, 0, -5, 0, 16), (2, 0, -3, 0, 16),        # east colonnade
    (-3, 0, -30, 0, 10), (-1, 0, -30, 0, 10),    # north cross-wall
    (1, 0, -30, 0, 10),
    (-3, 0, -6, 0, 10), (1, 0, -6, 0, 10),       # south cross-wall, gap kept
]

PLAYER = [0, 1, 8]
EXIT = [-10, 0, -66]
EXIT_TILE = (-3, -17)
START_TILE = (0, 1)

HAZARDS = [
    ("SpikesHazard3", "spikes", 2, -34),
    ("SpikesHazard4", "spikes", -6, -58),
    ("SpikesHazard5", "spikes", 6, -14),
    ("FireTrap2", "fire", -2, -22),
    ("FireTrap3", "fire", 10, -48),
]

LITTER = [
    ("EntryCouch1", "couch", (-6, 0, -2), 90),
    ("EntryCouch2", "couch", (-6, 0, -6), 90),
    ("ExitCouch", "couch", (-14, 0, -64), 0),
    ("NorthFlag", "flag", (-2, 0, -68), 0),
    ("NorthFlag2", "flag", (10, 0, -68), 0),
    ("BarrelW1", "barrel", (-14, 0, -44), 0),
    ("BarrelW2", "barrel", (-14, 0, -40), 0),
    ("BarrelE1", "barrel", (13, 0, -28), 0),
    ("BarrelE2", "barrel", (13, 0, -24), 0),
    ("BarrelN1", "barrel", (2, 0, -62), 0),
    ("BarrelN2", "barrel", (4, 0, -62), 0),
    ("BarrelS1", "barrel", (-10, 0, -2), 0),
    ("BarrelS2", "barrel", (10, 0, -4), 0),
]

VOXELGI_POS = [0, 0, -30]
VOXELGI_SIZE = [40, 20, 92]

# Floor dressing palette learned from Level 2's tile distribution
# ((item, orient), weight). Assigned per tile by stable hash so the mix is
# position-stable and reads as the shipped blue/grey checkerboard.
FLOOR_PALETTE = [((0, 10), 17), ((1, 10), 15), ((1, 0), 8), ((0, 0), 6)]


def _floor_variant(x: int, z: int) -> tuple[int, int]:
    """Picks a floor tile art variant for grid cell (x, z)."""
    rng = random.Random((x * 73856093) ^ (z * 19349663) ^ 0x9E3779B9)
    total = sum(w for _, w in FLOOR_PALETTE)
    roll = rng.uniform(0, total)
    acc = 0
    for variant, weight in FLOOR_PALETTE:
        acc += weight
        if roll < acc:
            return variant
    return FLOOR_PALETTE[-1][0]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design the Level 5 grand hall.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level5")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    floor = {(x, z) for x in VESTIBULE_X for z in VESTIBULE_Z}
    floor |= {(x, z) for x in HALL_X for z in HALL_Z}
    floor -= set(LAKE_A) | set(LAKE_B)
    print(f"design: {len(floor)} floor tiles")

    # Perimeter follows the shipped Level 2 pattern (tall west/south blockers,
    # low east/north rims): the low rims keep room to knock enemies out of
    # the level, which a full tall enclosure would remove as a design choice.
    # Windows every 3rd tall cell (shipped convention; rims stay solid).
    wall = gen_walls(floor, window_stride=3)
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps perimeter: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)
    # Shaft-wall pit lining (shipped Level 2 look): without it the pit quads
    # read as flat black stickers floating in the air.
    lakes = set(LAKE_A) | set(LAKE_B)
    lining = pit_lining(set(floor), lakes)
    for cell in lining:
        assert cell not in wall, f"lining overlaps structure: {cell}"
        wall[cell] = lining[cell]
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, {len(lining)} lining)")

    dressing = [("player", float(PLAYER[0]), float(PLAYER[2])),
                ("exit", float(EXIT[0]), float(EXIT[2]))]
    dressing += [(n, float(x), float(z)) for n, _k, x, z in HAZARDS]
    dressing += [(n, float(p[0]), float(p[2])) for n, _s, p, _r in LITTER]

    ok = check_connectivity(set(floor), START_TILE, EXIT_TILE)
    ok = check_walls_touch_floor(set(floor), wall) and ok
    ok = check_no_wall_overlap(wall) and ok
    ok = check_dressing(set(floor), dressing) and ok
    from validate_layout import suggest_voxelgi
    suggest_voxelgi(set(floor))
    if not ok:
        return 1

    floor_path = os.path.join(args.out_dir, "floor.txt")
    wall_path = os.path.join(args.out_dir, "wall.txt")
    with open(floor_path, "w") as f:
        for (x, z) in sorted(floor):
            item, orient = _floor_variant(x, z)
            f.write(f"{x},0,{z},{item},{orient}\n")
    with open(wall_path, "w") as f:
        for (x, y, z) in sorted(wall):
            item, orient = wall[(x, y, z)]
            f.write(f"{x},{y},{z},{item},{orient}\n")
    verts, tris = generate(set(floor))
    nav_path = os.path.join(args.out_dir, "navmesh.txt")
    with open(nav_path, "w") as f:
        f.write(render_snippet(verts, tris))
    print(f"navmesh scaffold: {len(verts)} verts, {len(tris)} tris")

    spec = {
        "template": "Levels/level_3.tscn",
        "root_name": args.name,
        "uid": None,
        "packed_cells": os.path.join(args.out_dir, "packed_cells.tscn"),
        "navmesh_snippet": nav_path,
        "navmesh_id": "NavigationMesh_level5",
        "strip_litter": True,
        "strip_hazards": True,
        "strip_pits": True,
        "exit": EXIT,
        "hazard_patterns": {"spikes": "SpikesHazard2", "fire": "FireTrap1"},
        "extra_hazards": [{"name": n, "kind": k, "x": x, "z": z} for n, k, x, z in HAZARDS],
        "litter_placed": [{"name": n, "scene": s, "pos": list(p), "rot_y": r}
                          for n, s, p, r in LITTER],
        "player": PLAYER,
        "voxelgi": {"pos": VOXELGI_POS, "size": VOXELGI_SIZE},
        "gi_data": None,
        "gi_ext_id": "4_level5",
        "out": "Levels/level_5.tscn",
        "seed": 20260915,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

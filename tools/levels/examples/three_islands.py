#!/usr/bin/env python3
"""Worked example #5: a causeway level (Level 8) with corridor links.

Three islands run west to east (Godot +X): spawn island A, central arena B
with a lined 2x2 pit lake, and exit island C with an open east cliff for
knock-off finishes. Two long tall-railed corridors join them (the first
shipped use of layout.corridor()); hazards dot the hallways with a clean
dodge line down one side. Enemies path the full length; players kite around
the lake and rails.

Pipeline (mirrors the README):
    python tools/levels/examples/three_islands.py --out-dir tools/levels/out/l8proof
    pack -> assemble (spec.json) -> bake navmesh -> splice -> bake GI
    -> register in SceneTransition.levels -> run_tests.py -> capture.py
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from generate_navmesh import generate, render_snippet  # noqa: E402
from generate_walls import generate as gen_walls  # noqa: E402
from generate_walls import pit_lining  # noqa: E402
from layout import compose, corridor, paint, room, touches  # noqa: E402
from validate_layout import check_connectivity, check_dressing  # noqa: E402
from validate_layout import check_no_wall_overlap  # noqa: E402
from validate_layout import check_walls_touch_floor  # noqa: E402
from validate_layout import suggest_voxelgi  # noqa: E402

# --- footprint: islands + causeways (tile coords, inclusive) ---
ISLE_A = room(0, 5, 4, 9)
LAKE = [(13, 5), (14, 5), (13, 6), (14, 6)]
ISLE_B = room(11, 17, 3, 9, holes=[(13, 14, 5, 6)])
ISLE_C = room(23, 28, 4, 9)
WALK1 = corridor(6, 10, 6, 7)
WALK2 = corridor(18, 22, 5, 6)

# Freestanding cover pillars near arena B's corners (x, y, z, item, orient).
PILLARS = [
    (24, 0, 8, 0, 10), (33, 0, 8, 0, 10),
    (24, 0, 18, 0, 10), (33, 0, 18, 0, 10),
]

PLAYER = [12, 1, 26]
EXIT = [108, 0, 30]
EXIT_TILE = (27, 7)
START_TILE = (3, 6)

HAZARDS = [
    ("SpikesA", "spikes", 18, 26),
    ("FireC1", "fire", 34, 30),
    ("SpikesC2a", "spikes", 80, 24),
    ("SpikesC2b", "spikes", 86, 24),
    ("FireB1", "fire", 48, 26),
    ("FireB2", "fire", 64, 30),
    ("SpikesC", "spikes", 100, 22),
]

LITTER = [
    ("SpawnFlag", "flag", (6, 0, 34), 0),
    ("ExitFlag", "flag", (104, 0, 34), 0),
    ("BarrelA", "barrel", (8, 0, 20), 0),
    ("CouchA", "couch", (18, 0, 20), 90),
    ("BarrelB", "barrel", (60, 0, 22), 0),
    ("CouchB", "couch", (48, 0, 34), 0),
    ("BarrelC", "barrel", (94, 0, 34), 0),
    ("CouchC", "couch", (100, 0, 20), 90),
]

VOXELGI_POS = [58, 0, 26]
VOXELGI_SIZE = [124, 20, 36]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design the Level 8 causeway.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level8")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    # Causeways abut (mouths stay wall-free as interior junctions).
    assert touches(WALK1.tiles, ISLE_A.tiles) and touches(WALK1.tiles, ISLE_B.tiles)
    assert touches(WALK2.tiles, ISLE_B.tiles) and touches(WALK2.tiles, ISLE_C.tiles)
    floor, side_tiers = compose(ISLE_A, ISLE_B, ISLE_C, WALK1, WALK2)
    print(f"design: {len(floor)} floor tiles")

    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps walls: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)
    lining = pit_lining(set(floor), LAKE)
    assert lining, "lake must get shaft-wall lining"
    assert not (set(lining) & set(wall)), "lining collides with walls"
    wall.update(lining)
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, lake lined)")

    dressing = [("player", float(PLAYER[0]), float(PLAYER[2])),
                ("exit", float(EXIT[0]), float(EXIT[2]))]
    dressing += [(n, float(x), float(z)) for n, _k, x, z in HAZARDS]
    dressing += [(n, float(p[0]), float(p[2])) for n, _s, p, _r in LITTER]

    ok = check_connectivity(set(floor), START_TILE, EXIT_TILE)
    ok = check_walls_touch_floor(set(floor), wall) and ok
    ok = check_no_wall_overlap(wall) and ok
    ok = check_dressing(set(floor), dressing) and ok
    suggest_voxelgi(set(floor))
    if not ok:
        return 1

    floor_path = os.path.join(args.out_dir, "floor.txt")
    wall_path = os.path.join(args.out_dir, "wall.txt")
    variants = paint(set(floor))
    with open(floor_path, "w") as f:
        for (x, z) in sorted(floor):
            item, orient = variants[(x, z)]
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
        "navmesh_id": "NavigationMesh_level8",
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
        "gi_ext_id": "4_level8",
        "out": "Levels/level_8.tscn",
        "seed": 20260918,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

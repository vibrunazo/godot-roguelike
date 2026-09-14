#!/usr/bin/env python3
"""Worked example #7: a symmetric finale arena (Level 10), "The Crucible".

An 11x11 championship arena: low cliff rims on ALL four sides (maximum
knock-off potential), four symmetric 1x2 pit lakes with shaft lining, a
central 2x2 cover block, and a symmetric hazard ring (4 fires + 4 corner
spikes). Spawn west, exit east. The cover is one lone center pillar with
4 m+ of clear floor in every direction, so no thin navmesh sliver can wedge
enemies — enforced by check_cover_clearances.

Pipeline (mirrors the README):
    python tools/levels/examples/crucible.py --out-dir tools/levels/out/l10proof
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
from layout import compose, room  # noqa: E402
from validate_layout import check_connectivity, check_cover_clearances  # noqa: E402
from validate_layout import check_dressing  # noqa: E402
from validate_layout import check_no_wall_overlap  # noqa: E402
from validate_layout import check_walls_touch_floor  # noqa: E402
from validate_layout import suggest_voxelgi  # noqa: E402

# --- 11x11 arena (x/z 0..10), all rims low cliffs, four 1x2 pit lakes ---
ALL_LOW = {"n": -1, "s": -1, "w": -1, "e": -1}
LAKE_RECTS = [(3, 3, 3, 4), (7, 7, 3, 4), (3, 3, 6, 7), (7, 7, 6, 7)]
ARENA = room(0, 10, 0, 10, edge=ALL_LOW, holes=LAKE_RECTS)

# Four symmetric 1x2 pit lakes: tile coords (x, z).
LAKES = [
    [(3, 3), (3, 4)],
    [(7, 3), (7, 4)],
    [(3, 6), (3, 7)],
    [(7, 6), (7, 7)],
]

# Lone center pillar (x, y, z, item, orient) on tile (5, 5): 4 m+ of clear
# floor to every lake face, so all passages stay wide. (A 2x2 block of
# same-orient cells is invalid construction: adjacent run meshes overlap and
# trip check_no_wall_overlap, and stacked runs leave a 1 m seam. One cell
# cannot overlap anything.)
PILLARS = [
    (11, 0, 11, 0, 10),
]

PLAYER = [6, 1, 22]
EXIT = [38, 0, 22]
EXIT_TILE = (9, 5)
START_TILE = (1, 5)

HAZARDS = [
    ("FireN", "fire", 22, 10),
    ("FireS", "fire", 22, 34),
    ("FireW", "fire", 10, 22),
    ("FireE", "fire", 34, 22),
    ("SpikesNW", "spikes", 6, 6),
    ("SpikesNE", "spikes", 38, 6),
    ("SpikesSW", "spikes", 6, 38),
    ("SpikesSE", "spikes", 38, 38),
]

LITTER = [
    ("SpawnFlag", "flag", (6, 0, 30), 0),
    ("ExitFlag", "flag", (38, 0, 14), 0),
    ("CouchA", "couch", (18, 0, 18), 90),
    ("CouchB", "couch", (26, 0, 26), 0),
    ("BarrelA", "barrel", (18, 0, 34), 0),
    ("BarrelB", "barrel", (30, 0, 10), 0),
]

VOXELGI_POS = [22, 0, 22]
VOXELGI_SIZE = [52, 20, 52]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design the Level 10 crucible.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level10")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    lakes_flat = [t for lake in LAKES for t in lake]
    floor, side_tiers = compose(ARENA)
    print(f"design: {len(floor)} floor tiles ({len(lakes_flat)} lake tiles)")

    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps walls: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)
    lining = pit_lining(set(floor), set(lakes_flat))
    assert lining, "crucible expects lake lining cells"
    for cell in sorted(lining):
        assert cell not in wall, f"lining overlaps a wall: {cell}"
        wall[cell] = (21, 0)
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, {len(lining)} lining)")

    dressing = [("player", float(PLAYER[0]), float(PLAYER[2])),
                ("exit", float(EXIT[0]), float(EXIT[2]))]
    dressing += [(n, float(x), float(z)) for n, _k, x, z in HAZARDS]
    dressing += [(n, float(p[0]), float(p[2])) for n, _s, p, _r in LITTER]

    ok = check_connectivity(set(floor), START_TILE, EXIT_TILE)
    ok = check_walls_touch_floor(set(floor), wall) and ok
    ok = check_no_wall_overlap(wall) and ok
    ok = check_cover_clearances(set(floor), set(lakes_flat), wall) and ok
    ok = check_dressing(set(floor), dressing) and ok
    suggest_voxelgi(set(floor))
    if not ok:
        return 1

    floor_path = os.path.join(args.out_dir, "floor.txt")
    wall_path = os.path.join(args.out_dir, "wall.txt")
    from layout import paint  # noqa: E402
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
        "navmesh_id": "NavigationMesh_level10",
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
        "gi_ext_id": "4_level10",
        "out": "Levels/level_10.tscn",
        "seed": 20260920,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

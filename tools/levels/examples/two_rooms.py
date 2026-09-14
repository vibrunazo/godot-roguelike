#!/usr/bin/env python3
"""Worked example #3: a two-room bridge level (Level 6), the first with no
per-level pit quads. Two large rooms joined by a railed bridge over the
void (bottomed by the template's giant abyss plane); the outer north/east
edges are low cliff rims so knocked-back enemies (and the careless) fall
out of the level, while west/south carry tall blockers.

Built from tools/levels/layout.py primitives (room/bridge/compose) so the
pattern is reusable: future levels compose the same parts differently.

Pipeline (mirrors the README):
    python tools/levels/examples/two_rooms.py --out-dir tools/levels/out/l6proof
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
from layout import bridge, compose, paint, room, touches  # noqa: E402
from validate_layout import check_connectivity, check_dressing  # noqa: E402
from validate_layout import check_no_wall_overlap  # noqa: E402
from validate_layout import check_walls_touch_floor  # noqa: E402
from validate_layout import suggest_voxelgi  # noqa: E402

# --- footprint: two 7x7 rooms joined by a 3x2 bridge (tile coords) ---
ROOM_A = room(-9, -3, -3, 3)
ROOM_B = room(1, 7, -3, 3)
SPAN = bridge(-2, 0, -1, 0, rails="low")

# Freestanding divider stubs (x, y, z, item, orient): tall, tiled every
# other slot like everything else. Kept clear of spawn, exit and the bridge
# mouths.
PILLARS = [
    (-7, 0, -1, 0, 10), (-5, 0, -1, 0, 10),  # west room stub (x -16..-8)
    (3, 0, 1, 0, 10), (5, 0, 1, 0, 10),        # east room stub (x 4..12)
]

PLAYER = [-22, 1, 6]
EXIT = [22, 0, -2]
EXIT_TILE = (5, -1)
START_TILE = (-6, 1)

HAZARDS = [
    ("SpikesHazard6", "spikes", -30, -6),
    ("SpikesHazard7", "spikes", 26, 10),
    ("FireTrap4", "fire", 10, -6),
]

LITTER = [
    ("RoomCouch1", "couch", (-30, 0, 10), 90),
    ("RoomCouch2", "couch", (26, 0, -6), 0),
    ("BarrelA1", "barrel", (-30, 0, -10), 0),
    ("BarrelB1", "barrel", (30, 0, 6), 0),
    ("SpawnFlag", "flag", (-18, 0, 10), 0),
    ("ExitFlag", "flag", (18, 0, 2), 0),
]

VOXELGI_POS = [-2, 0, 2]
VOXELGI_SIZE = [76, 20, 36]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design the Level 6 bridge level.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level6")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    assert touches(SPAN.tiles, ROOM_A.tiles), "bridge misses room A"
    assert touches(SPAN.tiles, ROOM_B.tiles), "bridge misses room B"
    floor, side_tiers = compose(ROOM_A, ROOM_B, SPAN)
    print(f"design: {len(floor)} floor tiles")

    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps walls: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)
    # No holes by construction, so no lining (holes elsewhere would be lined
    # with shaft walls and bottomed by the template abyss — no quads needed).
    lining = pit_lining(set(floor), set())
    assert not lining
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, no lining)")

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
        "navmesh_id": "NavigationMesh_level6",
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
        "gi_ext_id": "4_level6",
        "out": "Levels/level_6.tscn",
        "seed": 20260916,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

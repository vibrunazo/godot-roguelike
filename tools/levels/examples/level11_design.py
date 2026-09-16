#!/usr/bin/env python3
"""Level 11: The Nine Sanctuaries.

A 3x3 layout of 9 interconnected rooms linked by 8 bridges of varying styles
(low-railed cliff bridges, tall enclosed corridors, and open cliff spans).
Room 5 (Center Nexus) features a central 3x3 pit lake lined with shaft walls
(pit_lining) and flanked by 4 symmetric corner cover pillars keeping 4m+ clearance.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from generate_navmesh import generate, render_snippet
from generate_walls import generate as gen_walls
from generate_walls import pit_lining
from layout import bridge, compose, corridor, paint, room, touches
from validate_layout import check_connectivity, check_cover_clearances
from validate_layout import check_dressing
from validate_layout import check_no_wall_overlap
from validate_layout import check_walls_touch_floor
from validate_layout import suggest_voxelgi

# --- 9 Rooms (Tile Coordinates: 4m per tile) ---
# Row 2 (South: z in 14..18)
R1 = room(0, 4, 14, 18, edge={"w": 0, "s": 0})             # SW: Start Vestibule
R2 = room(7, 13, 15, 18, edge={"s": 0, "n": -1})           # S: Long Gallery
R3 = room(16, 20, 14, 18, edge={"s": -1, "e": -1})         # SE: Sunken Corner

# Row 1 (Center: z in 7..13)
R4 = room(0, 4, 7, 11, edge={"w": 0})                      # W: Western Colonnade
LAKE_RECTS = [(9, 11, 9, 11)]
R5 = room(7, 13, 7, 13, holes=LAKE_RECTS)                  # Center Nexus with 3x3 lake
LAKE = [(x, z) for x in range(9, 12) for z in range(9, 12)]
R6 = room(16, 20, 7, 11, edge={"e": -1})                   # E: Eastern Spikeway

# Row 0 (North: z in 0..5)
R7 = room(0, 4, 0, 4, edge={"w": 0, "n": -1})             # NW: Overlook
R8 = room(7, 13, 0, 3, edge={"n": 0, "s": -1})            # N: Northern Gallery
R9 = room(16, 21, 0, 5, edge={"n": 0, "e": 0})            # NE: Portal Sanctuary (Exit)

# --- 8 Interconnecting Bridges ---
B_1_2 = bridge(5, 6, 16, 17, rails="low", sides=("n", "s"))
B_2_3 = bridge(14, 15, 16, 17, rails="low", sides=("n", "s"))
B_1_4 = bridge(2, 2, 12, 13, rails="open", sides=("w", "e"))
B_4_7 = bridge(2, 2, 5, 6, rails="low", sides=("w", "e"))
B_4_5 = bridge(5, 6, 9, 10, rails="tall", sides=("n", "s"))
B_5_6 = bridge(14, 15, 9, 10, rails="low", sides=("n", "s"))
B_5_8 = bridge(9, 10, 4, 6, rails="tall", sides=("w", "e"))
B_8_9 = bridge(14, 15, 1, 2, rails="low", sides=("n", "s"))

# Four freestanding cover pillars in R5 corners (wx, wy, wz, item, orient)
PILLARS = [
    (15, 0, 15, 0, 10),  # NW in R5
    (27, 0, 15, 0, 10),  # NE in R5
    (15, 0, 27, 0, 10),  # SW in R5
    (27, 0, 27, 0, 10),  # SE in R5
]

PLAYER = [10, 1, 66]     # In R1 (tile 2, 16)
START_TILE = (2, 16)
EXIT = [78, 0, 10]       # In R9 (tile 19, 2)
EXIT_TILE = (19, 2)

HAZARDS = [
    ("SpikesW1", "spikes", 6, 36),
    ("SpikesE1", "spikes", 74, 36),
    ("FireSE1", "fire", 74, 66),
    ("FireNW1", "fire", 10, 10),
    ("FireN1", "fire", 42, 6),
]

LITTER = [
    ("SpawnFlag", "flag", (10, 0, 72), 0),
    ("ExitFlag", "flag", (82, 0, 10), 0),
    ("CouchR2", "couch", (42, 0, 70), 0),
    ("CouchR8", "couch", (42, 0, 4), 180),
    ("BarrelR1", "barrel", (6, 0, 62), 0),
    ("BarrelR3", "barrel", (78, 0, 62), 0),
    ("BarrelR7", "barrel", (6, 0, 14), 0),
    ("BarrelR9", "barrel", (82, 0, 18), 0),
]

VOXELGI_POS = [44, 0, 38]
VOXELGI_SIZE = [96, 20, 84]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design Level 11 (The Nine Sanctuaries).")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level11")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    # Verify bridge junctions
    assert touches(B_1_2.tiles, R1.tiles) and touches(B_1_2.tiles, R2.tiles)
    assert touches(B_2_3.tiles, R2.tiles) and touches(B_2_3.tiles, R3.tiles)
    assert touches(B_1_4.tiles, R1.tiles) and touches(B_1_4.tiles, R4.tiles)
    assert touches(B_4_7.tiles, R4.tiles) and touches(B_4_7.tiles, R7.tiles)
    assert touches(B_4_5.tiles, R4.tiles) and touches(B_4_5.tiles, R5.tiles)
    assert touches(B_5_6.tiles, R5.tiles) and touches(B_5_6.tiles, R6.tiles)
    assert touches(B_5_8.tiles, R5.tiles) and touches(B_5_8.tiles, R8.tiles)
    assert touches(B_8_9.tiles, R8.tiles) and touches(B_8_9.tiles, R9.tiles)

    parts = [R1, R2, R3, R4, R5, R6, R7, R8, R9,
             B_1_2, B_2_3, B_1_4, B_4_7, B_4_5, B_5_6, B_5_8, B_8_9]

    floor, side_tiers = compose(*parts)
    print(f"design: {len(floor)} floor tiles across 9 rooms and 8 bridges")

    # Dash-jump gap 1: leave an open 4m void between South Gallery (R2) and Grand Nexus (R5)
    # with no walls on either ledge for x in 8..12 (20m wide open jump front).
    for x in range(8, 13):
        side_tiers[(x, 13, "s")] = None
        side_tiers[(x, 15, "n")] = None

    # Dash-jump gap 2: small gap in the south wall of Portal Sanctuary (R9) and north rim
    # of Eastern Spikeway (R6) at x in (18, 19) to jump across the 4m void.
    for x in (18, 19):
        side_tiers[(x, 5, "s")] = None
        side_tiers[(x, 7, "n")] = None

    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)

    # Insert freestanding cover pillars
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps walls: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)

    # Generate pit lining for the central lake
    lining = pit_lining(set(floor), set(LAKE))
    assert lining, "central pit lake must have shaft-wall lining"
    assert not (set(lining) & set(wall)), "lining collides with existing walls"
    wall.update(lining)
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, lake lined)")

    dressing = [("player", float(PLAYER[0]), float(PLAYER[2])),
                ("exit", float(EXIT[0]), float(EXIT[2]))]
    dressing += [(n, float(x), float(z)) for n, _k, x, z in HAZARDS]
    dressing += [(n, float(p[0]), float(p[2])) for n, _s, p, _r in LITTER]

    ok = check_connectivity(set(floor), START_TILE, EXIT_TILE)
    ok = check_walls_touch_floor(set(floor), wall) and ok
    ok = check_no_wall_overlap(wall) and ok
    ok = check_cover_clearances(set(floor), set(LAKE), wall) and ok
    ok = check_dressing(set(floor), dressing) and ok
    suggest_voxelgi(set(floor))
    if not ok:
        print("Design validation failed!")
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
        "navmesh_id": "NavigationMesh_level11",
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
        "gi_ext_id": "4_level11",
        "out": "Levels/level_11.tscn",
        "seed": 20260922,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())

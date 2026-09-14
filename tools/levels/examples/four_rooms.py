#!/usr/bin/env python3
"""Worked example #4: a four-room ring level (Level 7) with dash-jump gaps.

Rooms snake R1 (tile 0,0) -> R2 south (+Z, Godot south) -> R3 west (-X) ->
R4 north (-Z), each pair separated by exactly one floor tile (4 m) so a
dash (>4 m) clears the gap. Bridges span R1<->R2, R2<->R3 and R3<->R4
(enemy pathing); R1<->R4 are adjacent with no bridge (jump shortcut).
Gap-facing edges stay OPEN (no walls at all, not even low rims) except a
few tall stub segments, so every adjacent pair stays jumpable; outer edges
carry walls (derivation defaults: tall on west/south, low rims east/north).
All directions below use the Godot axis convention (north = -Z).

Pipeline (mirrors the README):
    python tools/levels/examples/four_rooms.py --out-dir tools/levels/out/l7proof
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

# --- footprint: 7x7 rooms, 1-tile gaps (tile coords, inclusive) ---
# Edge letters are the generator's (n=min-z, s=max-z, w=min-x, e=max-x):
# gap-facing sides are open (None), outer sides keep derivation defaults
# (tall on west/max-z, low rims on east/min-z — the shipped L2 pattern).
ROOM1 = room(0, 6, 0, 6, edge={"s": None, "w": None})
ROOM2 = room(0, 6, 8, 14, edge={"n": None, "w": None})
ROOM3 = room(-8, -2, 8, 14, edge={"e": None, "n": None})
ROOM4 = room(-8, -2, 0, 6, edge={"s": None, "e": None})
# Gap-spanning bridges: single-row decks whose void-facing SHORT sides need
# explicit rails (the auto long-side pick would rail the room junctions).
# Outer bridges are 1 tile wide (single file); the middle stays 3 wide.
BR12 = bridge(3, 3, 7, 7, rails="low", sides=("w", "e"))
BR23 = bridge(-1, -1, 10, 12, rails="low", sides=("n", "s"))
BR34 = bridge(-5, -5, 7, 7, rails="low", sides=("w", "e"))

# Tall stub segments on gap fronts (very few: one 2-tile stub per front, so
# every adjacent pair keeps a wide jump opening). Keys are (floor tile,
# generator side); sides use the Godot convention (n=-Z, s=+Z, w=-X, e=+X).
STUBS: dict[tuple[int, int, str], int] = {
    (0, 6, "s"): 0, (1, 6, "s"): 0,      # R1 south front, west end
    (-2, 8, "e"): 0, (-2, 9, "e"): 0,    # R3 east front, south end
    (-8, 6, "s"): 0, (-7, 6, "s"): 0,    # R4 south front, west end
    (0, 0, "w"): 0, (0, 1, "w"): 0,      # R1 west front, south end
}

PLAYER = [10, 1, 14]
EXIT = [-18, 0, 10]
EXIT_TILE = (-5, 2)
START_TILE = (2, 3)

HAZARDS = [
    ("SpikesR1", "spikes", 14, 10),
    ("SpikesR2", "spikes", 8, 52),
    ("FireR3", "fire", -18, 48),
    ("SpikesR4", "spikes", -26, 16),
    ("FireR4", "fire", -28, 12),
    # Spike gauntlet on the narrow south bridge deck (tile -5,7).
    ("SpikesB1", "spikes", -19, 29),
    ("SpikesB2", "spikes", -17, 29),
    ("SpikesB3", "spikes", -19, 31),
    ("SpikesB4", "spikes", -17, 31),
]

LITTER = [
    ("SpawnFlag", "flag", (6, 0, 22), 0),
    ("ExitFlag", "flag", (-14, 0, 14), 0),
    ("BarrelR1", "barrel", (22, 0, 6), 0),
    ("CouchR1", "couch", (24, 0, 20), 90),
    ("BarrelR2", "barrel", (22, 0, 36), 0),
    ("CouchR2", "couch", (6, 0, 52), 0),
    ("BarrelR3", "barrel", (-10, 0, 56), 0),
    ("CouchR3", "couch", (-26, 0, 36), 90),
    ("BarrelR4", "barrel", (-10, 0, 10), 0),
]

VOXELGI_POS = [-2, 0, 30]
VOXELGI_SIZE = [68, 20, 68]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design the Level 7 ring level.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="Level7")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    # Jump contract: adjacent rooms exactly one tile apart (dashable 4 m).
    assert ROOM2.tiles and ROOM1.tiles
    assert min(z for _, z in ROOM2.tiles) - max(z for _, z in ROOM1.tiles) == 2
    assert min(x for x, _ in ROOM2.tiles) - max(x for x, _ in ROOM3.tiles) == 2
    assert min(z for _, z in ROOM3.tiles) - max(z for _, z in ROOM4.tiles) == 2
    assert min(x for x, _ in ROOM1.tiles) - max(x for x, _ in ROOM4.tiles) == 2
    # Bridges abut (mouths stay wall-free as interior junctions).
    assert touches(BR12.tiles, ROOM1.tiles) and touches(BR12.tiles, ROOM2.tiles)
    assert touches(BR23.tiles, ROOM2.tiles) and touches(BR23.tiles, ROOM3.tiles)
    assert touches(BR34.tiles, ROOM3.tiles) and touches(BR34.tiles, ROOM4.tiles)

    floor, side_tiers = compose(ROOM1, ROOM2, ROOM3, ROOM4, BR12, BR23, BR34)
    print(f"design: {len(floor)} floor tiles")

    # Stub walls land on open gap edges, so apply them after compose (every
    # stub tile must currently be open — anything else is a design clash).
    assert all(side_tiers[k] is None for k in STUBS)
    side_tiers.update(STUBS)
    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)
    # Jump lines must stay open mid-front: no tall cell may stand on the gap
    # bands except the explicit STUBS and outer corner caps (single-cell ends
    # of perpendicular tall runs). Gap row z=7 -> wall rows 14,15; gap col
    # x=-1 -> wall cols -2,-1. Both candidate cells per stub side are allowed
    # (the generator tiles one of the pair).
    allowed: set[tuple[int, int]] = set()
    for tx, tz, side in STUBS:
        if side == "s":
            allowed.update({(2 * tx, 2 * tz + 2), (2 * tx + 1, 2 * tz + 2)})
        elif side == "n":
            allowed.update({(2 * tx, 2 * tz), (2 * tx + 1, 2 * tz)})
        elif side == "w":
            allowed.update({(2 * tx, 2 * tz), (2 * tx, 2 * tz + 1)})
        else:
            allowed.update({(2 * tx + 2, 2 * tz), (2 * tx + 2, 2 * tz + 1)})
    for wx, wy, wz in wall:
        if wy != 0 or (wx, wz) in allowed:
            continue
        mid_row = wz in (14, 15) and -14 <= wx <= 11
        mid_col = wx in (-2, -1) and 2 <= wz <= 27
        assert not (mid_row or mid_col), f"tall wall blocks jump gap: {(wx, wy, wz)}"
    print(f"design: {len(wall)} walls, jump fronts open")

    # No interior holes by construction (every gap reaches the outer void).
    lining = pit_lining(set(floor), set())
    assert not lining

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
        "navmesh_id": "NavigationMesh_level7",
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
        "gi_ext_id": "4_level7",
        "out": "Levels/level_7.tscn",
        "seed": 20260917,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

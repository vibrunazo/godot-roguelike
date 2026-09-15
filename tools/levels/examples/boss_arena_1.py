#!/usr/bin/env python3
"""Worked example #8: the first boss arena, "Boss Arena 1".

A medium 9x9 arena with no pits and no hazards: four symmetric
freestanding pillar obstacles, open center for a big boss body, player
spawn west and exit east. Edges follow regular rules: open south cliff,
north walled on the east half only, tall east/west walls. The
WaveObjective carries the Akira boss via the `boss_resources` spec key,
so the wave is exactly the boss. Reusable: later boss arenas copy this
recipe with their own boss resources.

Pipeline (mirrors the README):
    python tools/levels/examples/boss_arena_1.py --out-dir tools/levels/out/boss1proof
    pack -> assemble (spec.json, incl. boss_resources) -> bake navmesh
    -> splice -> bake GI -> register routing in SceneTransition.boss_arenas
    (NOT in the levels rotation) -> run_tests.py -> capture.py
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
from layout import compose, paint, room  # noqa: E402
from validate_layout import check_connectivity, check_dressing  # noqa: E402
from validate_layout import check_no_wall_overlap  # noqa: E402
from validate_layout import check_walls_touch_floor  # noqa: E402
from validate_layout import suggest_voxelgi  # noqa: E402

# --- 9x9 arena (tiles x/z 0..8), no pits, no hazards ---
# Regular edge rules: the south rim is fully open (knock-off cliff), the
# north rim is walled on the east half only, east/west keep default tall
# walls. Two room parts compose the split north edge.
ARENA_W = room(0, 4, 0, 8, edge={"n": None, "s": None})
ARENA_E = room(5, 8, 0, 8, edge={"s": None})

# Four symmetric freestanding pillar obstacles (x, y, z, item, orient),
# kept to the corners-ish tiles so the center stays open for the boss.
PILLARS = [
    (4, 0, 4, 0, 10), (12, 0, 4, 0, 10),
    (4, 0, 12, 0, 10), (12, 0, 12, 0, 10),
]

PLAYER = [6, 1, 18]
EXIT = [30, 0, 18]
EXIT_TILE = (7, 4)
START_TILE = (1, 4)

LITTER = [
    ("SpawnFlag", "flag", (6, 0, 26), 0),
    ("ExitFlag", "flag", (30, 0, 10), 0),
    ("CouchA", "couch", (14, 0, 26), 90),
    ("BarrelA", "barrel", (22, 0, 30), 0),
]

VOXELGI_POS = [18, 0, 18]
VOXELGI_SIZE = [44, 20, 44]


def main() -> int:
    ap = argparse.ArgumentParser(description="Design Boss Arena 1.")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="BossArena1")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    floor, side_tiers = compose(ARENA_W, ARENA_E)
    print(f"design: {len(floor)} floor tiles")

    wall = gen_walls(floor, window_stride=3, side_tiers=side_tiers)
    seen: set[tuple[int, int, int]] = set()
    for wx, wy, wz, item, orient in PILLARS:
        assert (wx, wy, wz) not in wall, f"pillar overlaps walls: {(wx, wy, wz)}"
        assert (wx, wy, wz) not in seen, f"pillar listed twice: {(wx, wy, wz)}"
        seen.add((wx, wy, wz))
        wall[(wx, wy, wz)] = (item, orient)
    lining = pit_lining(set(floor), set())
    assert not lining, "boss arena must have no pits"
    print(f"design: {len(wall)} walls ({len(PILLARS)} pillars, no pits)")

    dressing = [("player", float(PLAYER[0]), float(PLAYER[2])),
                ("exit", float(EXIT[0]), float(EXIT[2]))]
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
        "navmesh_id": "NavigationMesh_bossarena1",
        "strip_litter": True,
        "strip_hazards": True,
        "strip_pits": True,
        "exit": EXIT,
        "hazard_patterns": {"spikes": "SpikesHazard2", "fire": "FireTrap1"},
        "extra_hazards": [],
        "litter_placed": [{"name": n, "scene": s, "pos": list(p), "rot_y": r}
                          for n, s, p, r in LITTER],
        "boss_resources": ["res://Enemy/EnemyResources/enemy_akira_boss.tres"],
        "player": PLAYER,
        "voxelgi": {"pos": VOXELGI_POS, "size": VOXELGI_SIZE},
        "gi_data": None,
        "gi_ext_id": "4_bossarena1",
        "out": "Levels/boss_arena_1.tscn",
        "seed": 20260921,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

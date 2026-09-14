#!/usr/bin/env python3
"""Worked example: design a level twice as long as Level 2 by mirroring it.

This is the exact recipe Level 4 was built from. It reads a dump_cells.gd
dump of Level 2, mirrors the footprint 40m north (-10 floor cells, -20 wall
cells), carves a corridor through the seam, closes the new perimeter, and
writes the cell files, navmesh snippet and assemble_level.py spec.

Usage:
    python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn --out=/tmp/l2.txt
    python tools/levels/examples/double_level.py --cells /tmp/l2.txt --out-dir /tmp/l4
    python tools/levels/validate_layout.py --floor /tmp/l4/floor.txt --wall /tmp/l4/wall.txt \\
        --pits "0,-8;-4,-20;-8,-20;0,-48;-8,-60;-4,-60" --start 0,0 --goal -3,-17
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from generate_navmesh import generate, render_snippet  # noqa: E402
from validate_layout import check_connectivity, check_pit_coverage  # noqa: E402
from validate_layout import check_walls_touch_floor, load_cells, suggest_voxelgi  # noqa: E402

SHIFT_F = 10  # floor cells in -z (40m)
SHIFT_W = 20  # wall cells in -z (2m grid, same 40m)

# Seam corridor: walls in this band are removed between the halves.
CARVE_Z = (-18, -14)
CARVE_X = (-6, 2)

# West perimeter gap left by the mirror (style matches neighbours).
# Only the segments touching floor are filled: the mirrored notch rows have no
# floor beneath them, and Level 2 leaves its own notch unwalled, so the two
# segments over the void are omitted rather than left floating.
WEST_FILLS = [(-8, 0, wz, 0, 16) for wz in (-17, -15)]
# Far-north corner nubs (match the north-ring style).
CORNER_NUBS = [(-8, -1, -36, 0, 10), (4, -1, -36, 0, 10)]

PITS = [(0, -8), (-4, -20), (-8, -20), (0, -48), (-8, -60), (-4, -60)]
EXIT = [-12, 0, -68]
HAZARDS = [(5, -59), (-10, -65)]
VOXELGI_POS = [-4, 0, -32]
VOXELGI_SIZE = [32, 20, 88]
LEVEL_UID = "uid://cwg2eho4uk4ey"  # pinned so the example reproduces Level 4
# (omit/"uid" null in hand-written specs for a fresh random uid)


def main() -> int:
    ap = argparse.ArgumentParser(description="Mirror Level 2 into a 2x level design.")
    ap.add_argument("--cells", required=True, help="dump_cells.gd output for the source level")
    ap.add_argument("--out-dir", required=True, help="destination directory for cell/nav/spec files")
    ap.add_argument("--name", default="Level4")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    floor = load_cells(args.cells, "FLOOR")
    wall = load_cells(args.cells, "WALL")
    print(f"source: {len(floor)} floor, {len(wall)} wall cells")

    floor4 = dict(floor)
    for (x, z), v in floor.items():
        floor4[(x, z - SHIFT_F)] = v
    wall4 = dict(wall)
    for (x, y, z), v in wall.items():
        wall4[(x, y, z - SHIFT_W)] = v

    carved = [k for k in wall4 if CARVE_Z[0] <= k[2] <= CARVE_Z[1] and CARVE_X[0] <= k[0] <= CARVE_X[1]]
    for k in carved:
        del wall4[k]
    print(f"carved {len(carved)} seam walls")
    for wx, wy, wz, item, orient in WEST_FILLS + CORNER_NUBS:
        assert (wx, wy, wz) not in wall4
        wall4[(wx, wy, wz)] = (item, orient)
    print(f"design: {len(floor4)} floor, {len(wall4)} wall cells")

    ok = check_connectivity(set(floor4), (0, 0), (-3, -17))
    ok = check_pit_coverage(set(floor4), [(float(x), float(z)) for x, z in PITS]) and ok
    ok = check_walls_touch_floor(set(floor4), wall4) and ok
    suggest_voxelgi(set(floor4))
    if not ok:
        return 1

    floor_path = os.path.join(args.out_dir, "floor.txt")
    wall_path = os.path.join(args.out_dir, "wall.txt")
    with open(floor_path, "w") as f:
        for (x, z) in sorted(floor4):
            item, orient = floor4[(x, z)]
            f.write(f"{x},0,{z},{item},{orient}\n")
    with open(wall_path, "w") as f:
        for (x, y, z) in sorted(wall4):
            item, orient = wall4[(x, y, z)]
            f.write(f"{x},{y},{z},{item},{orient}\n")
    # Dressing pattern: duplicate every template prop 40m north into the new wing.
    template_text = open("Levels/level_2.tscn").read()
    litter_names = re.findall(r'\[node name="([^"]+)" parent="NavigationRegion3D/Litter"',
                              template_text)
    litter_copies = [{"name": n + "N", "from": n, "dx": 0, "dz": -40} for n in litter_names]
    print(f"litter copies: {len(litter_copies)}")

    verts, tris = generate(set(floor4))
    nav_path = os.path.join(args.out_dir, "navmesh.txt")
    with open(nav_path, "w") as f:
        f.write(render_snippet(verts, tris))
    print(f"navmesh: {len(verts)} verts, {len(tris)} tris")

    spec = {
        "template": "Levels/level_2.tscn",
        "root_name": args.name,
        "uid": LEVEL_UID,
        "packed_cells": os.path.join(args.out_dir, "packed_cells.tscn"),
        "navmesh_snippet": nav_path,
        "navmesh_id": "NavigationMesh_level4",
        "pit_pattern_from": "Pit2",
        "extra_pits": [{"name": f"Pit{i}", "x": x, "z": z}
                       for i, (x, z) in enumerate(PITS[2:], start=3)],
        "exit": EXIT,
        "hazard_pattern_from": "SpikesHazard2",
        "extra_hazards": [{"name": f"SpikesHazard{i}", "ext_id": "5_spikes", "x": x, "z": z}
                          for i, (x, z) in enumerate(HAZARDS, start=3)],
        "litter_copies": litter_copies,
        "player": None,
        "voxelgi": {"pos": VOXELGI_POS, "size": VOXELGI_SIZE},
        "gi_data": "res://Levels/GlobalIlluminationData/level_4_voxel_gi_data.res",
        "gi_ext_id": "4_level4",
        "out": "Levels/level_4.tscn",
        "seed": 20260914,
    }
    spec_path = os.path.join(args.out_dir, "spec.json")
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"wrote {floor_path}, {wall_path}, {nav_path}, {spec_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

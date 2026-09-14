#!/usr/bin/env python3
"""Generates a NavigationMesh snippet (vertices + polygons text) from floor cells.

Emits one quad per floor tile on a shared corner lattice so neighbouring tiles
share vertex indices (required: the pathfinder only crosses polygons that share
indices, not merely coincident coordinates). Triangles are wound for an upward
normal; gaps in the grid (pits) become holes automatically.

Usage:
    python tools/levels/generate_navmesh.py --floor F --out navmesh.txt [--height 0.6]
"""
from __future__ import annotations

import argparse
import sys

FLOOR_TILE = 4.0


def generate(floor: set[tuple[int, int]],
             height: float = 0.6) -> tuple[list[tuple[float, float, float]],
                                           list[tuple[int, int, int]]]:
    """Builds shared-lattice navmesh geometry for the given floor tiles."""
    corner_index: dict[tuple[int, int], int] = {}
    verts: list[tuple[float, float, float]] = []

    def corner_id(cx: int, cz: int) -> int:
        if (cx, cz) not in corner_index:
            corner_index[(cx, cz)] = len(verts)
            verts.append((float(cx * 2), height, float(cz * 2)))
        return corner_index[(cx, cz)]

    tris: list[tuple[int, int, int]] = []
    for (fx, fz) in sorted(floor):
        ax, az = 2 * fx, 2 * fz
        a = corner_id(ax, az)
        b = corner_id(ax, az + 2)
        c = corner_id(ax + 2, az + 2)
        d = corner_id(ax + 2, az)
        tris.append((a, b, c))
        tris.append((a, c, d))
    return verts, tris


def render_snippet(verts: list[tuple[float, float, float]],
                   tris: list[tuple[int, int, int]]) -> str:
    """Renders the .tscn sub_resource body lines for the mesh."""
    out = "vertices = PackedVector3Array("
    out += ", ".join(f"{x}, {y}, {z}" for x, y, z in verts)
    out += ")\npolygons = ["
    out += ", ".join(f"PackedInt32Array({a}, {b}, {c})" for a, b, c in tris)
    out += "]\n"
    return out


def load_floor(path: str) -> set[tuple[int, int]]:
    """Reads floor tiles from a dump_cells.gd file (ignores the WALL section)."""
    floor: set[tuple[int, int]] = set()
    section: str | None = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line in ("FLOOR", "WALL"):
                section = line
                continue
            if section == "WALL":
                continue
            x, _y, z, _item, _orient = (int(v) for v in line.split(","))
            floor.add((x, z))
    return floor


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate navmesh snippet from floor cells.")
    ap.add_argument("--floor", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--height", type=float, default=0.6)
    args = ap.parse_args()
    floor = load_floor(args.floor)
    verts, tris = generate(floor, args.height)
    with open(args.out, "w") as f:
        f.write(render_snippet(verts, tris))
    print(f"navmesh: {len(verts)} verts, {len(tris)} tris -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

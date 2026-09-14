#!/usr/bin/env python3
"""Generates perimeter wall cells around a floor footprint, plus shaft-wall
pit lining copied from shipped Level 2.

Grid geometry model (read this before emitting wall cells by hand):
- Floormap tiles are 4m x 4m; Wallmap cells are 2m x 2m x 4m.
- Each wall MESH is 4m wide and 1m thick (wall_map.tres AABB x -2..2,
  z -0.5..0.5), centered on its cell's grid point: an X-running wall at
  cell (wx, wz) covers world x wx*2-2..wx*2+2 (two cells wide) but only
  z wz*2-0.5..wz*2+0.5. Z-running walls (orient 16/22) are transposed.
- Consequence: cells on EVERY slot of a straight run overlap their
  neighbours by 2m of coplanar faces, which shimmers (z-fighting) in game.
  Shipped runs occupy every OTHER slot so 4m panels tile edge-to-edge with
  zero overlap area. Worked example: an 8m hole edge along X at world x
  -12..-4 is lined by cells wx=-5 and wx=-3, with mesh spans -12..-8 and
  -8..-4.
- Perpendicular crossings read as normal corners and stacked tiers share no
  visible faces, so only same-axis, same-tier area overlap counts.
  validate_layout.check_no_wall_overlap() encodes exactly this rule — run
  it on every new wall file.

Perimeter: for every floor tile side facing the OUTER void, emits ONE wall
cell at the odd offset (each 4m-wide mesh then spans exactly that tile side;
emitting every cell overlaps neighbours and z-fights). Sides facing interior
holes (pits) are deliberately left open: pits get lining instead (see
below). Orientations follow shipped-Level-2 conventions per side:
north/south edges use orientation 10 (north-ring style), west edges 16
(west-wall style), east edges 22 (east-wall style). Height tiers default to
the Level 2 pattern (tall west/max-z blockers, low east/min-z rims that keep
room for knock-outs); pass tiers to change them per side.

Height tiers (measured by raycast: floor top ~0.0): a y=-1 wall spans y
-4..0 and tops out flush with the floor, reading as a rim or inlay, so
freestanding architecture generally belongs at y=0 (span y 0..4, tops ~4.1).
Shipped Level 2 mixes both: tall y=0 walls on its west/south perimeters,
low y=-1 rims on north/east, and y=-1 pit lining everywhere. Top-down and
isometric captures hide the difference; verifying new architecture with a
low, near-walk-height camera angle catches tier mistakes.
With --windows N, every Nth cell of each straight run becomes a window
(item 1), keeping corners solid (default 0: solid, matching shipped y=-1
perimeters, which carry no windows).

Pit lining: shipped levels ring every interior floor hole with y=-1 shaft
walls whose inner faces drop from the rim to the pit quad, which is what
makes pits read as deep shafts instead of flat black stickers. Each wall
mesh is 4m wide (AABB x -2..2 in wall_map.tres) while grid cells are 2m, so
lining cells sit on every OTHER cell along each hole edge (odd offsets),
straddling the hole/floor boundary plane: north edges use orientation 0,
south 10, west 16, east 22 (Level 2 conventions). Use pit_lining() for this.

Interior pillars/dividers are design, not derivation: specify those by hand in
your design script and concatenate the files.

Usage:
    python tools/levels/generate_walls.py --floor F --out W [--windows 5]
"""
from __future__ import annotations

import argparse
import collections
import sys

FLOOR_TILE = 4.0
WALL_CELL = 2.0


def _interior_holes(floor: set[tuple[int, int]]) -> set[tuple[int, int]]:
    """Floor-grid gaps NOT connected to the outer void (i.e. pits)."""
    xs = [x for x, _ in floor]
    zs = [z for _, z in floor]
    x0, x1, z0, z1 = min(xs) - 1, max(xs) + 1, min(zs) - 1, max(zs) + 1
    dq = collections.deque(
        [(x, z) for x in (x0, x1) for z in range(z0, z1 + 1)
         if (x, z) not in floor]
        + [(x, z) for x in range(x0, x1 + 1) for z in (z0, z1)
           if (x, z) not in floor])
    seen = set(dq)
    while dq:
        cx, cz = dq.popleft()
        for n in ((cx + 1, cz), (cx - 1, cz), (cx, cz + 1), (cx, cz - 1)):
            if not (x0 <= n[0] <= x1 and z0 <= n[1] <= z1):
                continue
            if n in floor or n in seen:
                continue
            seen.add(n)
            dq.append(n)
    return {(x, z) for x in range(min(xs), max(xs) + 1)
            for z in range(min(zs), max(zs) + 1)
            if (x, z) not in floor and (x, z) not in seen}


def generate(floor: set[tuple[int, int]],
             window_stride: int = 0,
             tiers: dict[str, int] | None = None) -> dict[tuple[int, int, int], tuple[int, int]]:
    """Builds {(x, y, z): (item, orient)} perimeter walls for floor tiles."""
    # Runs keyed by (side): cells along one straight edge. One cell per tile
    # side at the ODD offset: each 4m-wide wall mesh then spans exactly one
    # tile side, so consecutive tiles tile seamlessly with no coplanar
    # overlap (emitting every cell overlaps neighbours by 2m and shimmers
    # with z-fighting; shipped long runs all use this spacing).
    # tiers maps side ("n"/"s"/"w"/"e") to wall height tier. The default
    # copies shipped Level 2: tall blockers on west/max-z, low flush rims on
    # east/min-z — the low rims keep room to knock enemies out of the level.
    if tiers is None:
        tiers = {"n": -1, "s": 0, "w": 0, "e": -1}
    holes = _interior_holes(floor)
    runs: dict[tuple[str, int], list[tuple[int, int, int, int]]] = {}
    for (fx, fz) in floor:
        sides = [
            # (side key, orient, cells if the neighbour is outer void)
            (("n", 2 * fz), 10, [(2 * fx + 1, tiers["n"], 2 * fz)]
             if (fx, fz - 1) not in floor and (fx, fz - 1) not in holes else []),
            (("s", 2 * fz + 2), 10, [(2 * fx + 1, tiers["s"], 2 * fz + 2)]
             if (fx, fz + 1) not in floor and (fx, fz + 1) not in holes else []),
            (("w", 2 * fx), 16, [(2 * fx, tiers["w"], 2 * fz + 1)]
             if (fx - 1, fz) not in floor and (fx - 1, fz) not in holes else []),
            (("e", 2 * fx + 2), 22, [(2 * fx + 2, tiers["e"], 2 * fz + 1)]
             if (fx + 1, fz) not in floor and (fx + 1, fz) not in holes else []),
        ]
        for key, orient, cells in sides:
            for c in cells:
                runs.setdefault(key, []).append((c[0], c[1], c[2], orient))
    wall: dict[tuple[int, int, int], tuple[int, int]] = {}
    for cells in runs.values():
        cells = sorted(set(cells))
        for i, (x, y, z, orient) in enumerate(cells):
            # Windows only in full-height runs: shipped low rims are solid.
            item = 1 if window_stride > 0 and y == 0 and i % window_stride == 2 else 0
            wall[(x, y, z)] = (item, orient)
    return wall


def pit_lining(floor: set[tuple[int, int]],
               holes: set[tuple[int, int]]) -> dict[tuple[int, int, int], tuple[int, int]]:
    """Rings interior floor holes with y=-1 shaft walls (Level 2 pattern).

    For every hole-tile side facing a floor tile, emits the odd-offset
    straddling wall cell (each 4m-wide mesh then covers the full tile side
    with no overlaps): north sides (2*fx+1, -1, 2*fz) orient 0, south
    (2*fx+1, -1, 2*fz+2) orient 10, west (2*fx, -1, 2*fz+1) orient 16,
    east (2*fx+2, -1, 2*fz+1) orient 22. All solid (item 0). Merging is
    idempotent: a lining cell already present (e.g. a hand-placed pillar in
    the same slot) is left as-is, since any y=-1 wall there preserves the
    shaft look and the presence contract.
    """
    lining: dict[tuple[int, int, int], tuple[int, int]] = {}
    for (fx, fz) in sorted(holes):
        sides = [
            ((fx, fz - 1), (2 * fx + 1, -1, 2 * fz), 0),
            ((fx, fz + 1), (2 * fx + 1, -1, 2 * fz + 2), 10),
            ((fx - 1, fz), (2 * fx, -1, 2 * fz + 1), 16),
            ((fx + 1, fz), (2 * fx + 2, -1, 2 * fz + 1), 22),
        ]
        for neighbour, cell, orient in sides:
            if neighbour not in floor:
                continue
            if cell in lining:
                continue
            lining[cell] = (0, orient)
    return lining


def load_floor(path: str) -> set[tuple[int, int]]:
    """Reads floor tiles from a dump_cells.gd file (ignores WALL section)."""
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
    ap = argparse.ArgumentParser(description="Generate perimeter walls from floor cells.")
    ap.add_argument("--floor", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--windows", type=int, default=0,
                    help="every Nth run cell becomes a window (0 = solid walls)")
    args = ap.parse_args()
    wall = generate(load_floor(args.floor), args.windows)
    with open(args.out, "w") as f:
        for (x, y, z) in sorted(wall):
            item, orient = wall[(x, y, z)]
            f.write(f"{x},{y},{z},{item},{orient}\n")
    print(f"perimeter: {len(wall)} walls -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

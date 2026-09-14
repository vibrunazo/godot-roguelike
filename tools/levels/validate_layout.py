#!/usr/bin/env python3
"""Design-time validation for level GridMap layouts (no engine needed).

Checks, for any floor/wall/pit design:
  1. Floor connectivity: every floor tile reachable from the start tile
     (4-neighbourhood). A disconnected tile is an unreachable island.
  2. Pit coverage: every interior floor gap is covered by a pit quad;
     boundary gaps connected to the outer void need none.
  3. Wall sanity: every wall footprint touches or overlaps the floor area
     (catches typos that fling walls into the void).
  4. VoxelGI suggestion: prints a center/size that encloses the footprint.

Cell files use the dump_cells.gd format ("x,y,z,item,orientation" lines;
FLOOR/WALL headers accepted and ignored). Coordinates are grid cells:
floor tiles are 4m, wall cells 2m, pit quads are given in world meters.

Usage:
    python tools/levels/validate_layout.py --floor F --wall W --pits "x,z;x,z"
        [--start x,z] [--goal x,z]
"""
from __future__ import annotations

import argparse
import collections
import sys

FLOOR_TILE = 4.0
WALL_CELL = 2.0


def load_cells(path: str, want: str) -> dict:
    """Reads one section of a dump_cells.gd file.

    `want` is "FLOOR" (keys (x, z)) or "WALL" (keys (x, y, z)). Files without
    headers are treated as containing only the wanted section, so a combined
    dump can feed both --floor and --wall.
    """
    cells: dict = {}
    section: str | None = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line in ("FLOOR", "WALL"):
                section = line
                continue
            if section is not None and section != want:
                continue
            x, y, z, item, orient = (int(v) for v in line.split(","))
            if want == "FLOOR":
                assert y == 0, f"floor cells must be y=0: {line}"
                cells[(x, z)] = (item, orient)
            else:
                cells[(x, y, z)] = (item, orient)
    return cells


def check_connectivity(floor: set[tuple[int, int]], start: tuple[int, int],
                       goal: tuple[int, int] | None = None) -> bool:
    """BFS over 4-neighbours; every tile must be reachable from start."""
    if start not in floor:
        print(f"FAIL: start tile {start} has no floor", file=sys.stderr)
        return False
    seen = {start}
    dq = collections.deque([start])
    while dq:
        cx, cz = dq.popleft()
        for n in ((cx + 1, cz), (cx - 1, cz), (cx, cz + 1), (cx, cz - 1)):
            if n in floor and n not in seen:
                seen.add(n)
                dq.append(n)
    ok = True
    if len(seen) != len(floor):
        print(f"FAIL: {len(floor) - len(seen)} unreachable tiles: "
              f"{sorted(set(floor) - seen)}", file=sys.stderr)
        ok = False
    if goal is not None and goal not in seen:
        print(f"FAIL: goal tile {goal} unreachable from {start}", file=sys.stderr)
        ok = False
    print(f"connectivity: {len(seen)}/{len(floor)} reachable from {start}")
    return ok


def check_walls_touch_floor(floor: set[tuple[int, int]],
                            wall: dict[tuple[int, int, int], tuple[int, int]]) -> bool:
    """Warns about wall footprints that touch no floor tile.

    Advisory only (always passes): shipped Level 3 contains freestanding
    backdrop walls, and notches are conventionally left unwalled (Level 2).
    Treat a warning as a prompt to look at a capture, not as a failure.
    """
    rects = [(fx * FLOOR_TILE - 0.1, fz * FLOOR_TILE - 0.1,
              fx * FLOOR_TILE + FLOOR_TILE + 0.1, fz * FLOOR_TILE + FLOOR_TILE + 0.1)
             for fx, fz in floor]
    warned: set[tuple[int, int]] = set()
    for (wx, _wy, wz) in wall:
        x0, x1 = wx * WALL_CELL, wx * WALL_CELL + WALL_CELL
        z0, z1 = wz * WALL_CELL, wz * WALL_CELL + WALL_CELL
        if not any(x0 <= rx1 and rx0 <= x1 and z0 <= rz1 and rz0 <= z1
                   for rx0, rz0, rx1, rz1 in rects):
            warned.add((wx, wz))
    for w in sorted(warned):
        print(f"WARN: wall {w} floats outside the floor area (backdrop?)")
    print(f"wall sanity: {len(wall) - len(warned)}/{len(wall)} walls touch the floor area")
    return True


# Wall mesh extents (wall_map.tres: 4m wide, 1m thick, centered on the cell
# grid point). X-running pieces (orient 0/10) span x +-2m, z +-0.5m;
# Z-running pieces (16/22) span x +-0.5m, z +-2m.
_X_RUN_ORIENTS = (0, 10)
_Z_RUN_ORIENTS = (16, 22)


def _mesh_rect(cell: tuple[int, int, int], orient: int) -> tuple[float, float, float, float]:
    """World-space mesh footprint for a wall cell (see extents above)."""
    x, _y, z = cell
    cx, cz = x * WALL_CELL, z * WALL_CELL
    if orient in _X_RUN_ORIENTS:
        return (cx - 2.0, cz - 0.5, cx + 2.0, cz + 0.5)
    if orient in _Z_RUN_ORIENTS:
        return (cx - 0.5, cz - 2.0, cx + 0.5, cz + 2.0)
    return (cx, cz, cx + WALL_CELL, cz + WALL_CELL)


def _mesh_axis(orient: int) -> str | None:
    if orient in _X_RUN_ORIENTS:
        return "x"
    if orient in _Z_RUN_ORIENTS:
        return "z"
    return None


def check_no_wall_overlap(wall: dict[tuple[int, int, int], tuple[int, int]]) -> bool:
    """Fails on coplanar mesh overlaps that shimmer with z-fighting.

    Only same-tier, same-axis pairs count: perpendicular crossings are normal
    corners, stacked tiers share no visible faces, and edge-touching runs
    (the shipped tiling) have zero overlap area.
    """
    cells = sorted(wall)
    bad: list[tuple[tuple[int, int, int], tuple[int, int, int]]] = []
    for i in range(len(cells)):
        a = cells[i]
        axisa = _mesh_axis(wall[a][1])
        if axisa is None:
            continue
        ax0, az0, ax1, az1 = _mesh_rect(a, wall[a][1])
        for j in range(i + 1, len(cells)):
            b = cells[j]
            if b[1] != a[1] or _mesh_axis(wall[b][1]) != axisa:
                continue
            bx0, bz0, bx1, bz1 = _mesh_rect(b, wall[b][1])
            if min(ax1, bx1) - max(ax0, bx0) > 0.01 and min(az1, bz1) - max(az0, bz0) > 0.01:
                bad.append((a, b))
    for a, b in bad[:10]:
        print(f"FAIL: coplanar wall overlap {a} x {b}", file=sys.stderr)
    if len(bad) > 10:
        print(f"FAIL: ... plus {len(bad) - 10} more overlaps", file=sys.stderr)
    if bad:
        print("overlap: INVALID (tile runs every other cell; see the grid model in generate_walls.py)")
    else:
        print(f"overlap: {len(cells)} walls tile cleanly")
    return not bad


def check_dressing(floor: set[tuple[int, int]],
                   points: list[tuple[str, float, float]]) -> bool:
    """Every placed thing (spawn, exit, hazards, props) must stand on floor.

    Points are world (x, z); each must fall inside a floor tile expanded by a
    0.5m prop-radius tolerance. This is the one placement class the other
    checks do not cover.
    """
    ok = True
    for name, px, pz in points:
        inside = any(fx * FLOOR_TILE - 0.5 <= px <= fx * FLOOR_TILE + FLOOR_TILE + 0.5
                     and fz * FLOOR_TILE - 0.5 <= pz <= fz * FLOOR_TILE + FLOOR_TILE + 0.5
                     for fx, fz in floor)
        if not inside:
            print(f"FAIL: {name} at ({px:g}, {pz:g}) stands outside the floor", file=sys.stderr)
            ok = False
    print(f"dressing: {len(points)} placements on floor" if ok else "dressing: INVALID")
    return ok


def suggest_voxelgi(floor: set[tuple[int, int]], margin: float = 4.0) -> None:
    """Prints a VoxelGI center/size enclosing the footprint plus margin."""
    xs = [x for x, _ in floor]
    zs = [z for _, z in floor]
    x0, x1 = min(xs) * FLOOR_TILE - margin, max(xs) * FLOOR_TILE + FLOOR_TILE + margin
    z0, z1 = min(zs) * FLOOR_TILE - margin, max(zs) * FLOOR_TILE + FLOOR_TILE + margin
    print(f"VoxelGI suggestion: center=({(x0 + x1) / 2:g}, 0, {(z0 + z1) / 2:g}) "
          f"size=({x1 - x0:g}, 20, {z1 - z0:g})")


def _parse_pair(s: str) -> tuple[int, int]:
    a, b = s.split(",")
    return int(a), int(b)


def main() -> int:
    ap = argparse.ArgumentParser(description="Validate a level GridMap layout.")
    ap.add_argument("--floor", required=True, help="Floor cell file (dump_cells format)")
    ap.add_argument("--wall", required=True, help="Wall cell file (dump_cells format)")
    ap.add_argument("--start", default="0,0", help="Player start tile x,z")
    ap.add_argument("--goal", default="", help="Exit tile x,z")
    ap.add_argument("--dressing", default="",
                    help='Placements "name,x,z;..." (world meters) that must stand on floor')
    args = ap.parse_args()

    floor = load_cells(args.floor, "FLOOR")
    wall = load_cells(args.wall, "WALL")
    print(f"floor={len(floor)} wall={len(wall)}")
    # No pit-quad coverage check: the template's giant abyss plane covers
    # every hole and cliff edge, so per-level quads are obsolete. Interior
    # holes still get shaft-wall lining (generate_walls.pit_lining), gated by
    # the rotation test's pit-lining check on the assembled scene.
    goal = _parse_pair(args.goal) if args.goal else None

    ok = check_connectivity(set(floor), _parse_pair(args.start), goal)
    ok = check_walls_touch_floor(set(floor), wall) and ok
    ok = check_no_wall_overlap(wall) and ok
    if args.dressing:
        points: list[tuple[str, float, float]] = []
        for entry in args.dressing.split(";"):
            if not entry.strip():
                continue
            name, sx, sz = entry.split(",")
            points.append((name.strip(), float(sx), float(sz)))
        ok = check_dressing(set(floor), points) and ok
    suggest_voxelgi(set(floor))
    print("VALID" if ok else "INVALID")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

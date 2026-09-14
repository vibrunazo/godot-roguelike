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
PIT_HALF = 4.0  # 8x8 pit quads


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


def check_pit_coverage(floor: set[tuple[int, int]],
                       pits: list[tuple[float, float]]) -> bool:
    """Every interior gap must lie under a pit quad; boundary gaps need none."""
    xs = [x for x, _ in floor]
    zs = [z for _, z in floor]
    holes = [(x, z) for x in range(min(xs), max(xs) + 1)
             for z in range(min(zs), max(zs) + 1) if (x, z) not in floor]

    def covered(fx: int, fz: int) -> bool:
        x0, x1 = fx * FLOOR_TILE, fx * FLOOR_TILE + FLOOR_TILE
        z0, z1 = fz * FLOOR_TILE, fz * FLOOR_TILE + FLOOR_TILE
        return any(px - PIT_HALF <= x0 and x1 <= px + PIT_HALF
                   and pz - PIT_HALF <= z0 and z1 <= pz + PIT_HALF
                   for px, pz in pits)

    uncovered = [h for h in holes if not covered(*h)]
    # Flood the void from outside the bbox: reached gaps are boundary notches.
    x0, x1, z0, z1 = min(xs) - 1, max(xs) + 1, min(zs) - 1, max(zs) + 1
    edge = ({(x0, z) for z in range(z0, z1 + 1)} | {(x1, z) for z in range(z0, z1 + 1)}
            | {(x, z0) for x in range(x0, x1 + 1)} | {(x, z1) for x in range(x0, x1 + 1)})
    dq = collections.deque([c for c in edge if c not in floor])
    seen_void = set(dq)
    while dq:
        cx, cz = dq.popleft()
        for n in ((cx + 1, cz), (cx - 1, cz), (cx, cz + 1), (cx, cz - 1)):
            if not (x0 <= n[0] <= x1 and z0 <= n[1] <= z1):
                continue
            if n in floor or n in seen_void:
                continue
            seen_void.add(n)
            dq.append(n)
    ok = True
    for h in uncovered:
        if h not in seen_void:
            print(f"FAIL: interior gap {h} has no pit quad", file=sys.stderr)
            ok = False
    print(f"pit coverage: {len(holes)} gaps, {len(uncovered)} boundary notches, "
          f"{len(pits)} quads")
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
    ap.add_argument("--pits", default="", help='Pit quad centers "x,z;x,z" (world meters)')
    ap.add_argument("--start", default="0,0", help="Player start tile x,z")
    ap.add_argument("--goal", default="", help="Exit tile x,z")
    args = ap.parse_args()

    floor = load_cells(args.floor, "FLOOR")
    wall = load_cells(args.wall, "WALL")
    print(f"floor={len(floor)} wall={len(wall)}")
    pits = [_parse_pair(p) for p in args.pits.split(";") if p.strip()] \
        if args.pits else []
    pits_f: list[tuple[float, float]] = [(float(x), float(z)) for x, z in pits]
    goal = _parse_pair(args.goal) if args.goal else None

    ok = check_connectivity(set(floor), _parse_pair(args.start), goal)
    ok = check_pit_coverage(set(floor), pits_f) and ok
    ok = check_walls_touch_floor(set(floor), wall) and ok
    suggest_voxelgi(set(floor))
    print("VALID" if ok else "INVALID")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

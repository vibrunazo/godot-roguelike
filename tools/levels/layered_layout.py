#!/usr/bin/env python3
"""Height-aware floor helpers; legacy layout.py remains a 2D design API.

Cells are (x,y,z)->(item,orientation). Vertical pitch .5m; flat floor tops
are y*.5m in the level template. Brush2 rises 2m (4 layers) toward local -X.
Only horizontal yaw orientations are accepted. Stairs have exactly two
connections: lower and upper landings, never side-entry or a same-level
shortcut. Use real collision navmesh baking before shipping a scene.
"""
from __future__ import annotations
from collections import deque
from pathlib import Path

Cell = tuple[int, int, int]
Cells = dict[Cell, tuple[int, int]]
# Godot GridMap orthogonal yaw indices, direction of ascending stair.
ASCENT = {0: (-1, 0), 10: (1, 0), 16: (0, 1), 22: (0, -1)}
STAIRS = 2
RISE_LAYERS = 4


def lift(tiles: dict[tuple[int, int], tuple[int, int]], layer: int) -> Cells:
    """Lift a painted 2D room to a floor layer without discarding elevation."""
    return {(x, layer, z): item for (x, z), item in tiles.items()}


def stair(x: int, layer: int, z: int, orientation: int = 0) -> Cells:
    """One 4x4m stair flight, lower height=layer*.5m, rise=2m."""
    if orientation not in ASCENT:
        raise ValueError("Stairs require a horizontal yaw: 0, 10, 16 or 22")
    return {(x, layer, z): (STAIRS, orientation)}


def landings(cell: Cell, orientation: int) -> tuple[Cell, Cell]:
    """Return the lower/upper flat floor cells a stair must connect."""
    x, y, z = cell
    dx, dz = ASCENT[orientation]
    return (x - dx, y, z - dz), (x + dx, y + RISE_LAYERS, z + dz)


def validate(cells: Cells, start: Cell) -> None:
    """Reject floating stairs, overlapping vertical footprints and disconnection.

    Stacked rooms/underpasses are deliberately not supported by this first
    API. Add volumetric clearance checks before relaxing that restriction.
    """
    footprints: set[tuple[int, int]] = set()
    graph: dict[Cell, set[Cell]] = {c: set() for c in cells}
    for c, (item, orientation) in cells.items():
        x, y, z = c
        assert (x, z) not in footprints, f"stacked footprint unsupported: {c}"
        footprints.add((x, z))
        assert item in (0, 1, STAIRS), f"unknown floor item {item}"
        if item == STAIRS:
            for landing in landings(c, orientation):
                assert landing in cells and cells[landing][0] != STAIRS, f"missing flat stair landing: {landing}"
                graph[c].add(landing)
                graph[landing].add(c)
        else:
            for n in ((x-1,y,z), (x+1,y,z), (x,y,z-1), (x,y,z+1)):
                if n in cells and cells[n][0] != STAIRS:
                    graph[c].add(n)
    assert start in graph, "spawn floor cell absent"
    reached: set[Cell] = {start}
    pending = deque([start])
    while pending:
        for n in graph[pending.popleft()] - reached:
            reached.add(n)
            pending.append(n)
    assert reached == set(cells), f"{len(cells)-len(reached)} cells unreachable across elevations"


def write_cells(path: Path, cells: Cells) -> None:
    """Write the existing pack_cells.gd format preserving Y and orientation."""
    path.write_text("".join(f"{x},{y},{z},{item},{o}\n" for (x,y,z),(item,o) in sorted(cells.items())))


def scaffold(cells: Cells) -> str:
    """Height-aware preview only: sloped stair quads plus flat room quads.

    No wall erosion: assembler input only; MUST replace with a real bake.
    """
    from generate_navmesh import render_snippet
    vertices: list[tuple[float, float, float]] = []
    indices: dict[tuple[float, float, float], int] = {}
    triangles: list[tuple[int, int, int]] = []
    for (x,y,z),(item,orientation) in sorted(cells.items()):
        corners: list[int] = []
        for ox,oz in ((0,0),(0,4),(4,4),(4,0)):
            height = y * .5 + .35
            if item == STAIRS:
                dx,dz = ASCENT[orientation]
                height += ((ox-2)*dx+(oz-2)*dz+2)*.5
            vertex = (x*4+ox,height,z*4+oz)
            if vertex not in indices:
                indices[vertex] = len(vertices)
                vertices.append(vertex)
            corners.append(indices[vertex])
        a,b,c,d = corners
        triangles.extend(((a,b,c),(a,c,d)))
    return render_snippet(vertices, triangles)

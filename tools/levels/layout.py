#!/usr/bin/env python3
"""Composable floor-plan primitives for level design scripts.

Rooms, bridges and corridors are the recurring vocabulary of combat levels,
so they live here instead of being re-derived per level. A Part bundles floor
tiles with edge policies; compose() merges parts into the (floor tiles,
side overrides) pair that generate_walls.generate() consumes:

    from layout import room, bridge, compose
    west = room(-9, -3, -3, 3)
    east = room(1, 7, -3, 3)
    span = bridge(-2, 0, -1, 0)
    assert touches(span.tiles, west.tiles) and touches(span.tiles, east.tiles)
    floor, side_tiers = compose(west, east, span)
    wall = generate(floor, window_stride=3, side_tiers=side_tiers)

Edge-policy rules (enforced by generate(), not here):
- Overrides apply only where derivation would already emit a wall, i.e. on
  sides facing outer void. Sides facing another part's floor (junctions such
  as bridge mouths) stay wall-free automatically, and pit-hole sides belong
  to pit_lining().
- Rooms default to derivation tiers everywhere; bridges/corridors pin their
  long sides (rails "low"/"open"/"tall"; corridors are tall-railed bridges).

Tile coordinates are floor-grid cells (4m tiles); ranges are inclusive.
"""
from __future__ import annotations

import dataclasses

RAIL_TIERS: dict[str, int | None] = {"low": -1, "open": None, "tall": 0}

# Floor art mix measured from shipped Level 2 ((item, orient), weight).
# Assigned per tile by stable hash in paint(), so the mix is position-stable.
STANDARD_PALETTE: list[tuple[tuple[int, int], int]] = [
    ((0, 10), 17), ((1, 10), 15), ((1, 0), 8), ((0, 0), 6),
]


@dataclasses.dataclass
class Part:
    """One floor-plan piece: tiles plus edge policies for its boundary."""
    tiles: set[tuple[int, int]]
    edges: dict[tuple[int, int, str], int | None]  # (fx, fz, side) -> tier/None


def rect(x0: int, x1: int, z0: int, z1: int) -> set[tuple[int, int]]:
    """Inclusive tile rectangle. Empty range is a design error, fail loudly."""
    assert x0 <= x1 and z0 <= z1, f"inverted rect: {(x0, x1, z0, z1)}"
    return {(x, z) for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)}


def _boundary(tiles: set[tuple[int, int]], side: str) -> set[tuple[int, int]]:
    """Tiles on the extreme row/column of a tile set for one side.

    Letters follow generate_walls.generate(), which is Godot-conventional:
    "n" is min-z (engine-north, -z side), "s" is max-z, "w" is min-x,
    "e" is max-x. room(edge=) keys MUST use these same letters — they are
    looked up verbatim during derivation, so any other convention silently
    misses (tall defaults leak onto supposedly open sides).
    """
    if side == "n":
        m = min(z for _, z in tiles)
        return {(x, z) for x, z in tiles if z == m}
    if side == "s":
        m = max(z for _, z in tiles)
        return {(x, z) for x, z in tiles if z == m}
    if side == "w":
        m = min(x for x, _ in tiles)
        return {(x, z) for x, z in tiles if x == m}
    if side == "e":
        m = max(x for x, _ in tiles)
        return {(x, z) for x, z in tiles if x == m}
    raise ValueError(f"unknown side {side!r}")


def room(x0: int, x1: int, z0: int, z1: int, *,
         holes: list[tuple[int, int, int, int]] = (),
         edge: dict[str, int | None] | None = None) -> Part:
    """A solid tile block with optional rectangular holes punched out.

    holes entries are (hx0, hx1, hz0, hz1) inclusive tile rects. edge maps a
    side ("n"/"s"/"w"/"e") to a tier (or None for no wall) for that side's
    boundary tiles — e.g. a room with a cliff side keeps the derivation
    default everywhere except edge={"e": -1}.
    """
    tiles = rect(x0, x1, z0, z1)
    for hx0, hx1, hz0, hz1 in holes:
        tiles -= rect(hx0, hx1, hz0, hz1)
    assert tiles, "room punched empty by its holes"
    edges: dict[tuple[int, int, str], int | None] = {}
    for side, tier in (edge or {}).items():
        for fx, fz in _boundary(tiles, side):
            edges[(fx, fz, side)] = tier
    return Part(tiles, edges)


def bridge(x0: int, x1: int, z0: int, z1: int, *,
           rails: str = "low",
           sides: tuple[str, ...] | None = None) -> Part:
    """A narrow strip whose LONG sides carry rails; ends stay default.

    rails "low" (flush rims enemies can be knocked over), "open" (no walls
    at all) or "tall" (full-height blockers). The strip direction follows the
    longer axis (ties run along X) unless sides names the railed sides
    explicitly — needed for single-row gap spans, whose void-facing sides
    are the SHORT ones. Mouth tiles where the bridge meets other parts stay
    wall-free via the interior-junction rule.
    """
    assert rails in RAIL_TIERS, f"unknown rails {rails!r}"
    if sides is not None:
        assert set(sides) <= {"n", "s", "w", "e"}, f"bad sides {sides!r}"
        long_sides = tuple(sides)
    else:
        long_sides = ("n", "s") if x1 - x0 >= z1 - z0 else ("w", "e")
    tiles = rect(x0, x1, z0, z1)
    edges: dict[tuple[int, int, str], int | None] = {}
    for side in long_sides:
        for fx, fz in _boundary(tiles, side):
            edges[(fx, fz, side)] = RAIL_TIERS[rails]
    return Part(tiles, edges)


def corridor(x0: int, x1: int, z0: int, z1: int) -> Part:
    """An enclosed strip: tall blockers on both long sides.

    Same geometry mechanism as bridge(); the name documents intent (a
    passage enemies cannot be knocked out of, as opposed to an open span).
    """
    return bridge(x0, x1, z0, z1, rails="tall")


def touches(a: set[tuple[int, int]], b: set[tuple[int, int]]) -> bool:
    """True when any tile of a is 4-adjacent to any tile of b (a junction)."""
    for x, z in a:
        if ((x + 1, z) in b or (x - 1, z) in b
                or (x, z + 1) in b or (x, z - 1) in b):
            return True
    return False


def compose(*parts: Part) -> tuple[set[tuple[int, int]],
                                   dict[tuple[int, int, str], int | None]]:
    """Merges parts into (floor tiles, side overrides for generate()).

    Conflicting edge policies on the same tile side are a design error and
    fail loudly; identical duplicates merge silently.
    """
    floor: set[tuple[int, int]] = set()
    edges: dict[tuple[int, int, str], int | None] = {}
    for part in parts:
        floor |= part.tiles
        for key, tier in part.edges.items():
            if key in edges and edges[key] != tier:
                raise ValueError(f"conflicting edge policies at {key}: "
                                 f"{edges[key]} vs {tier}")
            edges[key] = tier
    assert floor, "composition is empty"
    return floor, edges


def paint(floor: set[tuple[int, int]],
          palette: list[tuple[tuple[int, int], int]] = STANDARD_PALETTE,
          salt: int = 0x9E3779B9) -> dict[tuple[int, int], tuple[int, int]]:
    """Assigns a floor art variant per tile by stable hash (position-stable,
    iteration-order independent). Returns {(x, z): (item, orient)}."""
    import random
    total = sum(w for _, w in palette)
    out: dict[tuple[int, int], tuple[int, int]] = {}
    for x, z in floor:
        rng = random.Random((x * 73856093) ^ (z * 19349663) ^ salt)
        roll = rng.uniform(0, total)
        acc = 0
        for variant, weight in palette:
            acc += weight
            if roll < acc:
                out[(x, z)] = variant
                break
        else:
            out[(x, z)] = palette[-1][0]
    return out

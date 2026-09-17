#!/usr/bin/env python3
"""Level 12: The Broken Procession — six rooms along five winding bridges.

Run with --out-dir tools/levels/out/l12, then pack and assemble spec.json.
Bake navigation and GI before final assembly. Use --finish after assembly
 to add the existing room encounter areas.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from generate_navmesh import generate, render_snippet
from generate_walls import generate as gen_walls, pit_lining
from layout import bridge, compose, paint, rect, room, touches
from validate_layout import (check_connectivity, check_cover_clearances,
                             check_dressing, check_no_wall_overlap,
                             check_walls_touch_floor)

# Inclusive 4m floor cells. A staggered procession around a broad open gulf:
# Portal Court <--- Sunken Shrine <--- Watch Hall
#                          ^4m jump window over tile row z=10
# Arrival ---> Banner Gallery ---> Ember Court
# The shrine's south rim (z=9) sits one void tile from the gallery's north
# rim (z=11): a 3-tile dash-jump window (x 9..11) links room 2 into room 5.
LAKE = rect(9, 10, 1, 2)
ROOMS = [room(0, 4, 10, 14), room(8, 13, 11, 14, edge={"n": -1}),
         room(17, 22, 10, 15, edge={"e": -1}),
         room(18, 22, 0, 5, edge={"n": 0, "e": -1}),
         room(7, 13, -1, 9, holes=[(9, 10, 1, 2)]),
         room(-4, 2, -2, 4, edge={"n": 0, "w": 0, "s": -1})]
BRIDGES = [bridge(5, 7, 12, 13, rails="low"),
           bridge(14, 16, 12, 12, rails="open"),
           bridge(20, 21, 6, 9, rails="low"),
           bridge(14, 17, 2, 3, rails="tall"),
           bridge(3, 6, 1, 2, rails="low")]
PLAYER = [10, 1, 50]
EXIT = [-6, 0, 2]
# Tall cover kept away from bridge mouths and the shrine pit.
PILLARS = [(37, 0, 23, 0, 10), (43, 0, 29, 0, 10),
           (39, 0, 3, 0, 10), (-3, 0, -1, 0, 10), (-3, 0, 5, 0, 10)]
HAZARDS = [("EmberFire", "fire", 82, 50),
           ("WatchSpikes", "spikes", 86, 18),
           ("ShrineSpikes", "spikes", 50, 14)]
LITTER = [("ArrivalFlag", "flag", [6, 0, 54], 0),
          ("GalleryFlag", "flag", [38, 0, 54], 0),
          ("GalleryCouch", "couch", [46, 0, 57], 0),
          ("ArrivalBarrel", "barrel", [4, 0, 44], 0),
          ("EmberBarrel", "barrel", [74, 0, 58], 0),
          ("WatchCouch", "couch", [86, 0, 3], 180),
          ("ShrineFlag", "flag", [44, 0, 16], 0),
          ("PortalFlag", "flag", [-10, 0, 2], 0),
          ("PortalBarrel", "barrel", [3, 0, -4], 0)]
SPAWNS = [("Arrival", 10, 50), ("BannerGallery", 44, 52),
          ("EmberCourt", 80, 52), ("WatchHall", 82, 12),
          ("SunkenShrine", 46, 10), ("PortalCourt", -4, 6)]


def finish(scene_path: Path) -> None:
    """Post-assembly wiring, idempotent: room encounter areas + GI reference.

    Re-running assemble_level.py resets the scene to the spec state (scaffold
    navmesh aside, no VoxelGIData reference), so every rebuild must redo this
    step: appending the RoomSpawnArea nodes and pinning the baked GI .res.
    """
    text = scene_path.read_text()
    if 'id="12_spawn"' not in text:
        pos = text.index('[sub_resource type="NavigationMesh"')
        text = text[:pos] + ('[ext_resource type="PackedScene" '
            'path="res://Levels/room_spawn_area.tscn" id="12_spawn"]\n\n') + text[pos:]
        for name, x, z in SPAWNS:
            text += (f'\n[node name="RoomSpawn{name}" parent="." '
                     'instance=ExtResource("12_spawn")]\n'
                     f'position = Vector3({x}, 0, {z})\nroom_name = "{name}"\n')
    if 'id="4_level12"' not in text:
        spawn_line = ('[ext_resource type="PackedScene" '
                      'path="res://Levels/room_spawn_area.tscn" id="12_spawn"]\n')
        text = text.replace(spawn_line, spawn_line + (
            '[ext_resource type="VoxelGIData" '
            'path="res://Levels/GlobalIlluminationData/'
            'level_12_voxel_gi_data.res" id="4_level12"]\n'), 1)
        gi = re.search(r'\[node name="VoxelGI"[^\n]*\n', text)
        assert gi, "VoxelGI block not found"
        end = text.index("\n\n", gi.start())
        text = text[:end] + '\ndata = ExtResource("4_level12")' + text[end:]
    scene_path.write_text(text)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default="tools/levels/out/l12")
    ap.add_argument("--finish", type=Path)
    args = ap.parse_args()
    if args.finish:
        finish(args.finish)
        return 0
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    assert len(ROOMS) == 6 and len(BRIDGES) == 5
    for i, span in enumerate(BRIDGES):
        assert touches(span.tiles, ROOMS[i].tiles)
        assert touches(span.tiles, ROOMS[i + 1].tiles)
    floor, edges = compose(*ROOMS, *BRIDGES)
    # Dash-jump window between Banner Gallery (R2, north rim z=11) and the
    # Sunken Shrine (R5, south rim z=9): the single void tile row z=10 gets
    # no walls on either front across x 9..11 (a 12 m opening; the shrine's
    # tall south wall stays on the flanking tiles, framing the gap).
    for x in range(9, 12):
        edges[(x, 11, "n")] = None  # gallery front over the void
        edges[(x, 9, "s")] = None   # shrine front over the void
    wall = gen_walls(floor, window_stride=3, side_tiers=edges)
    lining = pit_lining(floor, LAKE)
    assert not (set(lining) & set(wall))
    wall.update(lining)
    for x, y, z, item, orient in PILLARS:
        assert (x, y, z) not in wall
        wall[x, y, z] = (item, orient)
    dressing = [("player", PLAYER[0], PLAYER[2]), ("exit", EXIT[0], EXIT[2])]
    dressing += [(n, x, z) for n, _, x, z in HAZARDS]
    dressing += [(n, p[0], p[2]) for n, _, p, _ in LITTER]
    assert check_connectivity(floor, (2, 12), (-2, 0))
    assert check_walls_touch_floor(floor, wall)
    assert check_no_wall_overlap(wall)
    assert check_cover_clearances(floor, LAKE, wall)
    assert check_dressing(floor, dressing)
    variants = paint(floor)
    # Ordered stone courses distinguish bridges from mottled room floors.
    for span in BRIDGES:
        for tile in span.tiles:
            variants[tile] = (0, 10)
    (out / "floor.txt").write_text("".join(
        f"{x},0,{z},{variants[x,z][0]},{variants[x,z][1]}\n" for x, z in sorted(floor)))
    (out / "wall.txt").write_text("".join(
        f"{x},{y},{z},{v[0]},{v[1]}\n" for (x,y,z), v in sorted(wall.items())))
    verts, tris = generate(floor)
    (out / "navmesh.txt").write_text(render_snippet(verts, tris))
    spec = dict(template="Levels/level_3.tscn", root_name="Level12", uid=None,
        packed_cells=(out / "packed_cells.tscn").as_posix(),
        navmesh_snippet=(out / "navmesh.txt").as_posix(),
        navmesh_id="NavigationMesh_level12", strip_litter=True,
        strip_hazards=True, strip_pits=True, exit=EXIT, player=PLAYER,
        hazard_patterns={"spikes": "SpikesHazard2", "fire": "FireTrap1"},
        extra_hazards=[dict(name=n, kind=k, x=x, z=z) for n,k,x,z in HAZARDS],
        litter_placed=[dict(name=n, scene=s, pos=p, rot_y=r) for n,s,p,r in LITTER],
        voxelgi=dict(pos=[38, 0, 28], size=[116, 20, 80]), gi_data=None,
        gi_ext_id="4_level12", out="Levels/level_12.tscn", seed=20260917)
    (out / "spec.json").write_text(json.dumps(spec, indent=2))
    print(f"Level 12: six rooms, five bridges, {len(floor)} tiles, {len(wall)} walls")
    return 0


if __name__ == "__main__":
    sys.exit(main())

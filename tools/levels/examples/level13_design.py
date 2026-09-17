#!/usr/bin/env python3
"""Level 13: Twin Terrace — medium two-height court with two stair routes.

Lower western combat court and upper eastern gallery flank an open fissure.
Two 4m-wide stairs connect them in a loop. No underneath-floor play space.
Build using tools/levels/build_level.py after running this design script.
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from layout import room, paint
from layered_layout import lift, stair, validate, write_cells, scaffold
from generate_walls import generate
from validate_layout import check_no_wall_overlap, check_walls_touch_floor


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out-dir', default='tools/levels/out/l13')
    out = Path(ap.parse_args().out_dir)
    out.mkdir(parents=True, exist_ok=True)
    lower = room(-5, -1, -4, 4)
    upper = room(1, 5, -4, 4)
    cells = lift(paint(lower.tiles), 0) | lift(paint(upper.tiles), 4)
    cells |= stair(0, 0, -2, 10) | stair(0, 0, 2, 10)
    validate(cells, (-4,0,0))
    lower_edges = {(-1,z,'e'): None for z in (-2,2)}
    upper_edges = {(1,z,'w'): None for z in (-2,2)}
    # Low east rim gives a view over the upper terrace; tall outer walls
    # retain the familiar blue dungeon silhouette. Mouths must remain open.
    low_walls = generate(lower.tiles, window_stride=3, side_tiers=lower_edges)
    high_walls = generate(upper.tiles, window_stride=3, side_tiers=upper_edges)
    # Cover breaks projectile sightlines without crowding either stair mouth.
    low_walls[(-7,0,1)] = (0,10)
    high_walls[(9,0,-1)] = (0,10)
    for tiles,walls in ((lower.tiles,low_walls),(upper.tiles,high_walls)):
        assert check_no_wall_overlap(walls)
        assert check_walls_touch_floor(tiles,walls)
    write_cells(out/'floor.txt',cells)
    write_cells(out/'wall.txt',low_walls)
    write_cells(out/'wall_upper.txt',high_walls)
    (out/'navmesh.txt').write_text(scaffold(cells))
    spec = dict(template='Levels/level_3.tscn', root_name='Level13', uid=None,
        packed_cells=(out/'packed_cells.tscn').as_posix(),
        navmesh_snippet=(out/'navmesh.txt').as_posix(), navmesh_id='NavigationMesh_level13',
        strip_litter=True, strip_hazards=True, strip_pits=True,
        # Clear of the cover wall at (-14, 2); do not rely on physics to
        # eject the player from an intersecting spawn.
        player=[-10,1,6], exit=[18,2,2],
        # Full-width foundations meet the stair underside at y=0 and extend
        # through the abyss plane; no exposed horizontal ledges to walk on.
        supports=[dict(name='StairFoundationNorth',pos=[2,-2,-6],size=[4,4,4]),
                  dict(name='StairFoundationSouth',pos=[2,-2,10],size=[4,4,4])],
        wall_layers=[dict(name='WallmapUpper',height=2,
            packed_cells=(out/'packed_upper.tscn').as_posix())],
        hazard_patterns={'spikes':'SpikesHazard2'},
        extra_hazards=[dict(name='SpikesUpper',kind='spikes',x=14,y=2,z=14)],
        litter_placed=[dict(name='LowerFlag',scene='flag',pos=[-14,0,14],rot_y=0),
                      dict(name='UpperFlag',scene='flag',pos=[18,2,10],rot_y=0),
                      dict(name='LowerBarrel',scene='barrel',pos=[-14,0,-10],rot_y=0),
                      dict(name='UpperCouch',scene='couch',pos=[18,2,-10],rot_y=180)],
        voxelgi=dict(pos=[2,2,2],size=[52,20,44]), gi_data=None,
        gi_ext_id='4_level13',out='Levels/level_13.tscn',seed=20260918)
    (out/'spec.json').write_text(json.dumps(spec,indent=2))
    print(f'Twin Terrace: {len(cells)} cells, two stairs, floors 0m/2m')


if __name__ == '__main__':
    main()

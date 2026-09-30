---
name: build-level
description: Use when creating or editing a level or dungeon - GridMap floors and walls, pits, stairs, litter props, NavigationMesh bakes, VoxelGI bakes, player spawn and ExitPoint placement, or adding a level to the run (GlobalVars.dungeons, DungeonResource, boss arenas).
---

# Building or editing a level

**Full reference: `tools/levels/README.md`** (every tool, the end-to-end
pipeline, multi-floor levels, lessons learned). Read it before building.
Prefer the scripted pipeline in `tools/levels/` over hand-editing scenes; it
refuses to ship on engine errors.

## Contracts every level must meet

- **Inherit `Levels/level_template.tscn`.** It provides lighting, the sky, the
  wave spawner (`WaveObjective`), the fall-kill plane (`WorldBoundary`), the
  giant abyss plane (`Pit`) under every hole, and the exit (`ExitPoint`,
  unlocked by `WaveObjective.finished`).
- **GridMap metrics:** floors use `Levels/Gridmap/floormap.tres`
  (`cell_size = (4, 0.5, 4)`); walls use `Levels/Gridmap/wall_map.tres`
  (`cell_size = (2, 4, 2)`).
- **Pits are gaps in the floor.** Never add per-level pit quads: the template's
  abyss plane bottoms every hole. Ring interior holes with `y = -1` shaft
  walls (`pit_lining()` in the design tools). The kill plane sits below.
- **Navigation:** the `NavigationRegion3D` mesh must be a real bake that covers
  the floor, wraps walls and stays clear of pits (enemies must not path off
  ledges). Freestanding tall cover needs 3 m of clear floor to any pit edge,
  or the bake leaves slivers that wedge enemies. Re-bake after moving
  anything solid: the `NavmeshRebuilder` rebakes the level at runtime when a
  destructible breaks, so a stale committed bake silently turns into a fresh
  one mid-level.
- **Destructibles** (barrels) go under `NavigationRegion3D` (in `Litter`):
  only props under the region are carved into the bake and tracked by the
  `NavmeshRebuilder`. Their bodies use the `Props` layer, which is reserved
  for them; a static prop that never breaks stays on `World`.
- **VoxelGI:** bake per level to
  `Levels/GlobalIlluminationData/<level_name>_voxel_gi_data.res`, with a volume
  that encloses the playable floor, the spawn, pits and the exit. Anything
  placed in the level at bake time that moves must have `gi_mode = DISABLED`,
  or it bakes a permanent shadow. Every character (the player and every
  registered enemy) already does, and `test_voxel_gi` checks it. (Baking needs
  a display server; see the README.)
- **Spawn and exit:** place `Player` at the start and `ExitPoint` at the end;
  there must be a navigation path between them.
- Group decorative props under a `Litter` node.

## Adding it to the run

- Regular levels: create a `DungeonResource` in `Levels/DungeonResources/`
  (scene, difficulty and enemy-count bounds) and add it to
  `GlobalVars.dungeons` in `Singletons/global_vars.tscn`. The run picks the
  dungeon that fits each encounter.
- Boss arenas: also a `DungeonResource` in `GlobalVars.dungeons`, with
  `boss_at_level` set to the dungeon level that detours to it. Regular
  selection never picks an arena. The arena's `WaveObjective.boss_resources`
  names its bosses.
- `GlobalVars.dungeons` is the only level registry; nothing else lists
  levels.

## Verify

```bash
python run_tests.py test/test_level_rotation_nav.tscn
python capture.py map Levels/<level>.tscn --preset all
```

`test_level_rotation_nav` checks every level the run can load (fallback
rotation, dungeons and boss arenas): core nodes, baked GI, navmesh and GI
coverage, a spawn-to-exit path, pit lining, the abyss plane and cover
clearance.

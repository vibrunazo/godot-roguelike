# TODO

Open work only. Completed items are removed (git history keeps their write-ups).
Section numbers (§) point into the closed 2026-09-23 code review,
`docs/reviews/2026-09-23-code-review.md`, which explains each item.

---

## Known game bugs

1. **Level 10 lighting is stale.** Its 24 pit-lining walls were fixed in Phase A
   (they used a missing wall piece and were invisible), but its VoxelGI data was
   not rebaked; rebaking needs a display server (`tools/levels/bake_level_gi`).
2. **The melee enemy's hit window is only 0.030 s** (`Melee_2H_Attack_Chop`,
   `WeaponSlot:enabled` keys 0.790–0.820 s), about 2 physics ticks. It works on
   the physics clock at 60 Hz, but would become hit-or-miss if the physics tick
   rate were lowered. Consider a window of at least 0.05 s. (§3.9)
3. **Enemies get stuck in each other's paths and never reach their
   destinations.** Two tasks:
   - Fix the stuck crowds, and measure whether enemies avoiding each other
     (`NavigationAgent3D` avoidance) is worth its CPU cost on the target
     devices.
   - Give the AI's walk-to states (`AIMeander` and any other state that walks
     to a point) a timeout, so a blocked walk gives up instead of waiting
     forever.
4. **The landing blast item fires on tiny bumps.** It is meant to deal damage
   when the player lands from a fall, but a dash that bumps over a 1 cm step
   and drops back down triggers it too. Every airborne-to-grounded edge
   broadcasts `movement.landed` (`AirborneTracker`), and
   `passive_landing_blast` fires on all of them. Gate it on a minimum fall:
   height, fall speed, or `airborne_time`, which the event already carries.

## Decisions needed

5. **VoxelGI on mobile.** Decided: mobile uses the Mobile renderer. VoxelGI
   is Forward+-only, so it will *probably* be dropped (e.g. for LightmapGI or
   ambient lighting); not decided yet, and not urgent until touch input exists.
   Until then, avoid deepening the per-level VoxelGI dependency. (§3.9)
6. **Enemy meshes are included in GI baking**, against the old level rule that
   dynamic entities stay out of GI. Every enemy scene (melee, ranged, brute,
   firebomber, thunder mage, Akira) uses `gi_mode = STATIC`. It is harmless
   today, because enemies only arrive after the bake, from the wave. Either set
   them to disabled, or write the rule down as "anything placed in the level
   when GI is baked", which is what `test_voxel_gi` checks.

## Test suite bugs

7. **`test_brute_pit_corner_nav` no longer reproduces its bug.** Tall enemies
   used to cut pit corners and fall (fixed by the navigation agent tuning now
   in `Character`); on today's Level 2 the old tuning passes too. Build a
   fixture (e.g. an arena variant with an L-shaped pit) where the old tuning
   fails, and test it there.

## Features

8. **Player active abilities.** Four ability slots, bound by default to the
   keyboard keys 1 to 4 (as `InputMap` actions, so they can be rebound).
   The first test ability is a fireball.

## Architecture backlog

9. **Data-driven attacks (`AttackData` resources).** Every attack and combo
   step is its own hand-built state node, with combo branches and timings
   spread across state scripts and scenes. An `AttackData` resource
   (animation, damage, knockback, combo window, audio) played by one generic
   attack state would let new weapons and enemy attacks be authored as data.
10. **Rig and bone-attachment decoupling.** `animated_player.tscn` and
    `animated_enemy.tscn` hand-place their skeleton attachments (`WeaponSlot`,
    foot bones); reusing animations across skeletons breaks when a track
    references an attachment that is missing. Bind sockets from one component
    at setup, and keep gameplay logic off animation method tracks where
    possible.

Items 11 to 15 are what the closed code review left for later: none is a
defect.

11. **Mobile performance workstream** (with decision 5). A physics tick-rate
    axis for the tests (`--physics-tps`, to catch tick-dependent code before
    anyone lowers the rate to save battery), count-based budgets per level
    (nodes, bodies, particles, lights, draw calls), a worst-case benchmark
    scenario logged as a trend, and profiling on a real target phone. (§3.9)
12. **Tooling:** run the suites in parallel (`run_tests.py -j N`: about 0.7 s
    of each suite is engine startup); resolve UIDs inside binary `.res` files
    in the lint (a headless GDScript step); a pre-commit hook that runs the
    lint. (§4.3, §4.4, §5.2)
13. **Hang prevention that does not rely on the agent:** block direct
    `godot` calls in the agent harness (a Claude Code `PreToolUse` hook or
    permission rule pointing at the runners), and prototype an engine-side
    self-kill autoload for headless runs. (§5.2)
14. **A `CharacterController` base** for `PlayerInputComponent` and
    `AIStateMachine`, whose `command_*`/`order_*` methods are duplicated
    pairs today. (§5.3)
15. **Scratch harness:** let checks in `.scratch/` extend the test harness,
    and let `run_scratch.py` run a `.tscn`, so verifying a change in a scene
    never pushes agents toward `test/`. (§5.4)

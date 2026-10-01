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

## Test suite bugs

7. **`test_brute_pit_corner_nav` no longer reproduces its bug.** Tall enemies
   used to cut pit corners and fall (fixed by the navigation agent tuning now
   in `Character`); on today's Level 2 the old tuning passes too. Build a
   fixture (e.g. an arena variant with an L-shaped pit) where the old tuning
   fails, and test it there.

## Features

8. **Active ability follow-ups** (the system itself is in; see
   `docs/plans/active_abilities_plan.md`):
   - Migrate `RangedEnemy` (and the other casters) to an ability slot with
     the Fireball, dropping its bespoke attack state and spawner signal. It
     changes their timing, so retune them together.
   - A pick-up dialog (a close-up of the book, take it or leave it) and a
     replace-slot choice when every slot is full. Today a book the player
     cannot take stays on the floor with a message, and gear equipped with
     full slots skips its ability with only a warning in the log.
   - Mana regen and a mana bar, so abilities can cost mana (costs already
     work in `AbilityResource`; the Fireball is cooldown-only).
   - Item difficulty tiers for level spawns, drops and the shop
     (`GlobalVars.level_items` and the shop deal from every tier today).
   - Abilities with their own behavior (a leap, a channel): a slot state can
     only release a payload and caster effects today.
   - Secondary bindings for `ability_1`..`ability_4` (gamepad, mouse).

16. **Destructibles follow-ups** (the system is in: `Destructible`, the
    explosive barrel; see AGENTS.md §5):
    - Movement collision: barrels (and future solid destructibles) do not
      block the player or enemies. Adding it means deciding how it interacts
      with the baked navmeshes.
    - A real explosion look: the barrel blast reuses the ground-AOE visuals
      (rings, scorch disc, sparks). Add a fire burst at the barrel.
    - Radial knockback: `DamageArea` only knocks up (`knockback_force`);
      give it an outward-from-center option, so explosions push characters
      away.

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

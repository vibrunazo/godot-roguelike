# TODO

Open work only. Completed items are removed (git history keeps their write-ups).
The full review, the reasoning behind each item, and the phased plan (Phases A–D)
are in `CODE_REVIEW.md`; section numbers below point there.

---

## Known game bugs

1. **Level 10 lighting is stale.** Its 24 pit-lining walls were fixed in Phase A
   (they used a missing wall piece and were invisible), but its VoxelGI data was
   not rebaked; rebaking needs a display server (`tools/levels/bake_level_gi`).
2. **The melee enemy's hit window is only 0.030 s** (`Melee_2H_Attack_Chop`,
   `WeaponSlot:enabled` keys 0.790–0.820 s), about 2 physics ticks. It works on
   the physics clock at 60 Hz, but would become hit-or-miss if the physics tick
   rate were lowered. Consider a window of at least 0.05 s. (§3.9)
5. **The camera keeps the first level's height floor.** `CameraRig3D` records
   the lowest height it may follow down to once, in `_ready()`. A player carried
   into the next level is reparented and moved, not re-readied, so the floor
   stays at the first level's spawn height: on a level that spawns lower, the
   camera would not follow the player down to it. Recreating the player per
   level (item 11) fixes this for free; until then, re-base the floor when the
   level places the carried player (`level_template.gd`).
6. **An enemy that tries to attack while stunned loses its attack and wanders
   off.** `AIAttack.enter()` starts the attack cooldown when the mind decides
   to attack, before the body accepts the order. A refused order (the body is
   stunned or falling) still costs the whole cooldown, so the mind drops back
   to `AIMeander`, which cannot attack either and walks away from a player
   standing in range. Seen with the ranged enemy landing stunned from its
   spawn; a player's hit landing as the enemy decides to attack does the same.
   Start the cooldown only when the order is accepted; first add a failing
   regression test (an attack attempted while stunned must still be available
   once the stun ends).

## Decisions needed

3. **VoxelGI on mobile.** Decided: mobile uses the Mobile renderer. VoxelGI
   is Forward+-only, so it will *probably* be dropped (e.g. for LightmapGI or
   ambient lighting); not decided yet, and not urgent until touch input exists.
   Until then, avoid deepening the per-level VoxelGI dependency. (§3.9)
9. **Enemy meshes are included in GI baking, against AGENTS.md §6.3.** Every
   enemy scene (melee, ranged, brute, firebomber, thunder mage, Akira) uses
   `gi_mode = STATIC`. It is harmless today, because enemies only arrive after
   the bake, from the wave. Either set them to disabled (matching the rule) or
   narrow the rule to "anything placed in the level when GI is baked", which is
   what `test_voxel_gi` checks.

## Test suite bugs

Every suite now runs on the harness (Phase B step 4 is done).

10. **`test_brute_pit_corner_nav` no longer reproduces its bug.** Tall enemies
    used to cut pit corners and fall (fixed by the navigation agent tuning now
    in `Character`); on today's Level 2 the old tuning passes too. Build a
    fixture (e.g. an arena variant with an L-shaped pit) where the old tuning
    fails, and test it there.

## Architecture backlog

7. **Data-driven attacks (`AttackData` resources).** Attacks and combos are
    wired through string state names (`"SlashAttack"`, `"EnemyAttack"`, ...) with
    combo branches and timings spread across state scripts and scenes. An
    `AttackData` resource (animation, damage, knockback, combo window, audio)
    played by one generic attack state would let new weapons and enemy attacks
    be authored as data. Related: §2.2 (string state names).
8. **Rig and bone-attachment decoupling.** `animated_player.tscn` and
    `animated_enemy.tscn` hand-place their skeleton attachments (`WeaponSlot`,
    foot bones); reusing animations across skeletons breaks when a track
    references an attachment that is missing. Bind sockets from one component
    at setup, and keep gameplay logic off animation method tracks where
    possible.
11. **Recreate the player between levels instead of reparenting it.** Today
    `SceneTransition.load_scene_path()` reparents the live player node into
    the autoload (`player_cache`) and `LevelTemplate._ready()` swaps it in for
    the level's own `Player`, then calls `cancel_movement_and_abilities()` to
    scrub the leftovers. Every piece of per-level runtime state (timers,
    tweens, `_ready()`-time snapshots like the camera floor in item 5, status
    visuals, state-machine wiring) then has to be cleaned by hand, and each
    one missed is a bug. Instead, keep the run state that should persist
    (health, equipped gear and purchase counts, granted passives, anything
    else the run owns) in a plain resource or `ProgressionState`, let each
    level instantiate a fresh `Player`, and apply that state to it on spawn.
    `cancel_movement_and_abilities()` and the `player_cache` reparenting then
    go away. `test_level_transition_reset` covers today's carry-over and would
    become the contract for the new one.
12. **Make the lint green** (`python tools/lint_project.py`; its output is
    the exact list). This comes before any new feature work. 14
    `hardcoded-load` and 8 `compat-wording` findings are the D9 alias and
    fallback cleanup (§2.6, §2.7). The 27 `long-function` findings are
    functions to split: 18 production functions over 40 lines (the
    worst: `Character._ready()`, `EnemyLeapingDodge.enter()` and
    `_find_best_landing_position()`, `WaveObjective.generate_wave_enemies()`,
    `ObjectiveTrail3D._render_trail()`, `CharacterAttack.enter()`), 8 tests
    over 60 and 1 tool over 80.
15. The remaining review phases: Phase C guardrails (docs, skills, lint,
    shared launcher, CI) and Phase D cleanup (aliases, fallbacks, registries,
    refactors). See the status table in §5.5.

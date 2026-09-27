# TODO

Open work only. Completed items are removed (git history keeps their write-ups).
The full review, the reasoning behind each item, and the phased plan (Phases A–D)
are in `CODE_REVIEW.md`; section numbers below point there.

---

## Known game bugs

1. **AI leaping dodge silently rewrites designer values.** `AILeapingDodge._ready()`
   (`StateMachine/AIStates/ai_leaping_dodge.gd:14-19`) changes `trigger_range` from
   3.5 to 5.0 when it equals the parent default, replaces `attack_state_name`
   when it is `"EnemyAttack"`, and forces `can_break_stun = false`. A designer who
   sets 3.5 in the inspector gets 5.0. (§2.8)
2. **Item heal percentage has an ambiguous unit.** `ItemResource.heal_percent`
   (`Items/item_resource.gd:62` and `:99`) treats values above 1.0 as percent and
   values up to 1.0 as a fraction, so `1.0` heals 100% but `1.5` heals 1.5%. Pick
   one unit and convert the item resources. (§2.5)
3. **Stopping speed depends on the physics tick rate.** `core_movement()`
   (`StateMachine/character_state.gd:110-111`) decelerates with
   `move_toward(velocity, 0, speed)` per tick, without `delta`. Harmless at a
   fixed 60 Hz, but lowering `physics_ticks_per_second` (e.g. to save battery on
   phones) would change how characters stop. (§2.10, §3.9)
4. **Status effects are cleaned up by node name.** `Character.cancel_movement_and_abilities()`
   (`Character/character.gd:766-769`) frees every descendant whose name starts
   with `Status` or contains `burning`, which would also free unrelated nodes
   with those names. (§2.1)
5. **Level 10 lighting is stale.** Its 24 pit-lining walls were fixed in Phase A
   (they used a missing wall piece and were invisible), but its VoxelGI data was
   not rebaked; rebaking needs a display server (`tools/levels/bake_level_gi`).
6. **The melee enemy's hit window is only 0.030 s** (`Melee_2H_Attack_Chop`,
   `WeaponSlot:enabled` keys 0.790–0.820 s), about 2 physics ticks. It works on
   the physics clock at 60 Hz, but would become hit-or-miss if the physics tick
   rate were lowered. Consider a window of at least 0.05 s. (§3.9)

## Decisions needed

7. **VoxelGI on mobile.** Decided: mobile uses the Mobile renderer. VoxelGI
   is Forward+-only, so it will *probably* be dropped (e.g. for LightmapGI or
   ambient lighting); not decided yet, and not urgent until touch input exists.
   Until then, avoid deepening the per-level VoxelGI dependency. (§3.9)
8. **A supported way to stop a wave.** Seven suites disable enemy waves by
   stripping `WaveObjective`'s script (`set_script(null)`), which also removes its
   cleanup and leaks the pre-instanced enemies. Give `WaveObjective` a documented
   stop method (freeing unspawned enemies) or move those suites to the test
   arena. Affected: `test_boss_arena_1`, `test_brute_level2_nav`,
   `test_brute_pit_corner_nav`, `test_combo_and_dash_cancel`,
   `test_level_13_stairs`, `test_level_13_tables`, `test_level_rotation_nav`.

## Test suite bugs (fix while migrating each suite to the harness, Phase B)

9. **Suites that assume 60 fps** (fail at `python run_tests.py --fps 20`):
   - `test_firebomber_enemy`: expects a target spawned in mid-air not to have
     fallen after one render frame.
   - `test_damage_flash_and_shake`: calls `core_movement(0.016, 8.0)` directly
     on a player that may not be on the floor.
   - `test_akira_boss`: inspects projectiles one render frame after spawning
     them (already freed at low fps), and compares trap areas at a
     frame-dependent moment.
10. **Hardcoded balance, art and key assertions** that break when designers
    tune values: see the tables in §3.1 (balance), §3.2 (art/VFX/layout) and
    §3.3 (physical keys).
11. **`test_brute_level2_nav` saves screenshots during headless runs**
    (`_save_screenshot`, line 136), which logs engine errors because there is no
    renderer. Screenshots belong in `capture.py`/`tools/capture/scenarios/`.
12. **`test_enemy_base.gd` is one 3,064-line `_ready()`.** Split it into feature
    suites during its migration. (§3.4)

## Architecture backlog

13. **Data-driven attacks (`AttackData` resources).** Attacks and combos are
    wired through string state names (`"SlashAttack"`, `"EnemyAttack"`, ...) with
    combo branches and timings spread across state scripts and scenes. An
    `AttackData` resource (animation, damage, knockback, combo window, audio)
    played by one generic attack state would let new weapons and enemy attacks
    be authored as data. Related: §2.2 (string state names).
14. **Rig and bone-attachment decoupling.** `animated_player.tscn` and
    `animated_enemy.tscn` hand-place their skeleton attachments (`WeaponSlot`,
    foot bones); reusing animations across skeletons breaks when a track
    references an attachment that is missing. Bind sockets from one component
    at setup, and keep gameplay logic off animation method tracks where
    possible.
15. The remaining review phases: Phase B migrations, Phase C guardrails (docs,
    skills, lint, shared launcher, CI), Phase D cleanup (aliases, fallbacks,
    registries, refactors). See §5.5.

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
   camera would not follow the player down to it. Re-base the floor when the
   level places the carried player (`level_template.gd`).

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

## Test suite bugs (fix while migrating each suite to the harness, Phase B)

4. **Migrate the remaining suites to the harness** (14 left; list them with
    `grep -L "test/lib/test_suite.gd" test/test_*.gd`). The whole suite passes
    at `--fps 20`. While migrating, remove the hardcoded balance and art
    assertions listed in §3.1 (balance) and §3.2 (art/VFX/layout). No test
    calls a private method any more; two still read private fields:
    `WaveObjective._enemy_difficulties` (`test_enemy_base`) and
    `AttributeComponent._dots` (`test_level_transition_reset`).
6. **`test_enemy_base.gd` is one 3,064-line `_ready()`.** Split it into feature
    suites during its migration. (§3.4)

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
15. The remaining review phases: Phase B migrations, Phase C guardrails (docs,
    skills, lint, shared launcher, CI), Phase D cleanup (aliases, fallbacks,
    registries, refactors). See §5.5.

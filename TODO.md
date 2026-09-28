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

## Decisions needed

3. **VoxelGI on mobile.** Decided: mobile uses the Mobile renderer. VoxelGI
   is Forward+-only, so it will *probably* be dropped (e.g. for LightmapGI or
   ambient lighting); not decided yet, and not urgent until touch input exists.
   Until then, avoid deepening the per-level VoxelGI dependency. (§3.9)
## Test suite bugs (fix while migrating each suite to the harness, Phase B)

4. **Migrate the remaining suites to the harness** (34 left). Migrated so far:
    `test_character_rotation`, `test_ground_aoe_jump`, `test_debug_kill`,
    `test_self_hitstop`, `test_health_bar`, `test_enemy_thunder_mage`,
    `test_pause_menu`, `test_character_and_ai`, `test_damage_flash_and_shake`,
    `test_firebomber_enemy`, `test_akira_boss`, plus the new
    `test_frame_rate_invariance`, `test_attack_component`, `test_wave_objective`.
    The whole suite now passes at `--fps 20`. While migrating, remove the
    hardcoded balance, art and key assertions listed in §3.1 (balance), §3.2
    (art/VFX/layout) and §3.3 (physical keys; now only `test_jump_action`), and
    the private-method calls (still in 12 suites).
    - `test_combo_and_dash_cancel` is flaky (about 1 run in 12 at `--fps 12`):
      it still uses the level template's random wave enemy as its dummy, which
      can kill the player mid-test. Moving it to the arena fixes this.
5. **`test_brute_level2_nav` saves screenshots during headless runs**
    (`_save_screenshot`, line 136), which logs engine errors because there is no
    renderer. Screenshots belong in `capture.py`/`tools/capture/scenarios/`.
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

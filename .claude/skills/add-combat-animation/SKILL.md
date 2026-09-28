---
name: add-combat-animation
description: Use when adding or re-wiring an attack or combat animation for the player or an enemy - extracting an animation from a KayKit GLB into a .res, keying the WeaponSlot hit-window tracks, adding it to an AnimationPlayer library and an AnimationTree state machine.
---

# Adding a combat animation

## Where the assets are

- Animation GLBs: `Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/`
  (`Rig_Medium_CombatMelee.glb`, `Rig_Medium_General.glb`, `Rig_Medium_Movement.glb`, ...).
  The brute and the Akira boss use the large rig (`Rig_Large`).
- Character model GLBs: `Assets/KayKit_Assets/KayKit_GameDevTV_Enemies_Character_Pack_1.0/Characters/gltf/`.
- Extracted animations: `.../Rig_Medium/Animations/<AnimationName>.res`.

## 1. Extract the animation (headless)

The editor's "Save to File" import option is not available to a headless
agent. Write a throwaway script in `.scratch/` and run it through the runner:

```gdscript
# .scratch/extract_anim.gd
extends SceneTree

func _initialize() -> void:
	var glb: Node3D = load("res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Rig_Medium_CombatMelee.glb").instantiate() as Node3D
	var player: AnimationPlayer = glb.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation: Animation = player.get_animation("Melee_2H_Attack_Chop").duplicate() as Animation
	ResourceSaver.save(animation, "res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_2H_Attack_Chop.res")
	glb.free()
	quit(0)
```

```bash
python run_scratch.py .scratch/extract_anim.gd
```

## 2. Key the three WeaponSlot tracks

Every attack animation for the player or a melee enemy must carry these value
tracks on the weapon slot the attack uses (`WeaponSlot`, or `PunchSlot`,
`FeetSlot`, ... per the attack state's `weapon_slot` export), e.g.
`Rig_Medium/Skeleton3D/WeaponSlot:<property>`:

1. **`enabled`** (discrete): `false` at 0 s (wind-up), `true` at the strike
   apex (switches the hitbox `Area3D` on), `false` at the end of the strike
   (recovery). Keep the window at least ~0.05 s: shorter windows risk missing
   ticks if the physics rate is ever lowered.
2. **`attack_mode`** (discrete): `1` for a slash, `2` for a stab (drives which
   trail VFX shows).
3. **`vfx_threshold`** (continuous): an eased curve `1.0 -> 0.0 -> 1.0` that
   sweeps the slash-trail shader.

## 3. Wire it into the character

1. In `animated_player.tscn` / `animated_enemy.tscn` (or the large-rig
   equivalent), add the `.res` to the character's library on its
   `AnimationPlayer` (`PlayerAnimations` / `EnemyAnimations`).
2. In the `AnimationTree` root state machine, add a node for the animation.
   - `WalkSpace -> <Attack>`: manual advance (`advance_mode = 1`).
   - `<Attack> -> WalkSpace`: switch at end (`switch_mode = 2`), auto advance
     (`advance_mode = 2`), with a short crossfade like the existing attacks.
   - The `AnimationTree` must keep `callback_mode_process = PHYSICS`, or the
     hit window depends on the render frame rate.
3. Point the attack state (`CharacterAttack`) at it with
   `attack_animation_name`, and set its `weapon_slot` export.

## 4. Verify

- Record it: `python capture.py anim <character scene> --state <AttackState> --video`
  (see the `capture-media` skill).
- The hit landing at every frame rate is covered by
  `test/test_frame_rate_invariance.gd`; extend it if you added a new timed
  mechanic, and run `python run_tests.py`.

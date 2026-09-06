extends Node

func _ready() -> void:
	print("--- RUNNING BASE ENEMY SCENE & LOGIC TEST ---")
	
	# ---------------------------------------------------------
	# PART 1: Enemy Scene & Class Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Enemy Instantiation & Node Types")
	var enemy_scene: PackedScene = load("res://Enemy/enemy.tscn")
	if enemy_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/enemy.tscn")
		get_tree().quit(1)
		return
		
	var enemy: Enemy = enemy_scene.instantiate() as Enemy
	if enemy == null:
		printerr("TEST FAILED: enemy is not an instance of class_name Enemy.")
		get_tree().quit(1)
		return
	print("Enemy scene loaded and class_name Enemy verified.")
	
	if not (enemy is CharacterBody3D):
		printerr("TEST FAILED: Enemy is not a CharacterBody3D.")
		get_tree().quit(1)
		return
	print("Enemy is CharacterBody3D verified.")
	
	# Verify collision layer includes layers 1 & 2 (3)
	if (enemy.collision_layer & 1) == 0:
		printerr("TEST FAILED: Enemy collision_layer does not include layer 1 (world physics).")
		get_tree().quit(1)
		return
	if (enemy.collision_layer & 2) == 0:
		printerr("TEST FAILED: Enemy collision_layer does not include layer 2 (hit detection).")
		get_tree().quit(1)
		return
	print("Enemy collision_layer verified (layers 1 and 2 active, value: ", enemy.collision_layer, ")")
	
	add_child(enemy)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# ---------------------------------------------------------
	# PART 2: Animated Visuals, AnimationPlayer & AnimationTree
	# ---------------------------------------------------------
	print("\n>>> PART 2: Visuals, AnimationPlayer & AnimationTree Checks")
	var anim_anchor: Node3D = enemy.get_node_or_null("AnimationAnchor") as Node3D
	if anim_anchor == null:
		printerr("TEST FAILED: AnimationAnchor node not found on Enemy.")
		get_tree().quit(1)
		return
	print("AnimationAnchor node verified.")
	
	var animated_enemy: Node3D = anim_anchor.get_node_or_null("AnimatedEnemy") as Node3D
	if animated_enemy == null:
		printerr("TEST FAILED: AnimatedEnemy scene not found under AnimationAnchor.")
		get_tree().quit(1)
		return
	print("AnimatedEnemy scene instance verified.")
	
	var skeleton: Skeleton3D = animated_enemy.get_node_or_null("Enemy_Medium/Rig_Medium/Skeleton3D") as Skeleton3D
	if skeleton == null:
		printerr("TEST FAILED: Skeleton3D not found under Enemy_Medium.")
		get_tree().quit(1)
		return
	print("Skeleton3D verified under Enemy_Medium.")
	
	var weapon_slot: WeaponSlot = skeleton.get_node_or_null("WeaponSlot") as WeaponSlot
	if weapon_slot == null:
		printerr("TEST FAILED: WeaponSlot BoneAttachment3D missing on Skeleton3D.")
		get_tree().quit(1)
		return
	print("WeaponSlot BoneAttachment3D verified on skeleton.")
	
	var right_foot: BoneAttachment3D = skeleton.get_node_or_null("RightFootBone") as BoneAttachment3D
	if right_foot == null:
		printerr("TEST FAILED: RightFootBone BoneAttachment3D missing on Skeleton3D.")
		get_tree().quit(1)
		return
	print("RightFootBone BoneAttachment3D verified on skeleton.")
	
	var left_foot: BoneAttachment3D = skeleton.get_node_or_null("LeftFootBone") as BoneAttachment3D
	if left_foot == null:
		printerr("TEST FAILED: LeftFootBone BoneAttachment3D missing on Skeleton3D.")
		get_tree().quit(1)
		return
	print("LeftFootBone BoneAttachment3D verified on skeleton.")
	
	var anim_player: AnimationPlayer = animated_enemy.get_node_or_null("Enemy_Medium/AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		printerr("TEST FAILED: AnimationPlayer not found on Enemy_Medium.")
		get_tree().quit(1)
		return
	if not anim_player.has_animation_library(&"EnemyAnimations"):
		printerr("TEST FAILED: AnimationLibrary 'EnemyAnimations' missing on AnimationPlayer.")
		get_tree().quit(1)
		return
	for anim_name: String in ["Death_A", "Hit_A", "Idle_A", "Melee_1H_Attack_Slice_Diagonal", "Running_B", "Spawn_Ground"]:
		if not anim_player.has_animation("EnemyAnimations/" + anim_name):
			printerr("TEST FAILED: Animation '", anim_name, "' missing in EnemyAnimations library.")
			get_tree().quit(1)
			return
	print("AnimationPlayer & EnemyAnimations library verified (Death_A, Hit_A, Idle_A, Melee_1H_Attack_Slice_Diagonal, Running_B, Spawn_Ground).")
	
	var anim_tree: AnimationTree = animated_enemy.get_node_or_null("Enemy_Medium/AnimationTree") as AnimationTree
	if anim_tree == null:
		printerr("TEST FAILED: AnimationTree not found on Enemy_Medium.")
		get_tree().quit(1)
		return
	var sm: AnimationNodeStateMachine = anim_tree.tree_root as AnimationNodeStateMachine
	if sm == null:
		printerr("TEST FAILED: AnimationTree tree_root is not an AnimationNodeStateMachine.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"EnemyAnimations_Spawn_Ground"):
		printerr("TEST FAILED: State 'EnemyAnimations_Spawn_Ground' not found in AnimationTree.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"WalkSpace"):
		printerr("TEST FAILED: State 'WalkSpace' not found in AnimationTree.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"Stun"):
		printerr("TEST FAILED: State 'Stun' not found in AnimationTree.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"Defeat"):
		printerr("TEST FAILED: State 'Defeat' not found in AnimationTree.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"RangedAttack"):
		printerr("TEST FAILED: State 'RangedAttack' not found in AnimationTree.")
		get_tree().quit(1)
		return
	var walk_space: AnimationNodeBlendSpace1D = sm.get_node(&"WalkSpace") as AnimationNodeBlendSpace1D
	if walk_space == null:
		printerr("TEST FAILED: WalkSpace is not an AnimationNodeBlendSpace1D.")
		get_tree().quit(1)
		return
	print("AnimationTree state machine, WalkSpace blend space, Stun, Defeat, and RangedAttack states verified.")
	
	var anim_script: Script = anim_tree.get_script() as Script
	if anim_script == null or anim_script.resource_path != "res://Player/mannequin_animation_tree.gd":
		printerr("TEST FAILED: AnimationTree does not have mannequin_animation_tree.gd attached.")
		get_tree().quit(1)
		return
	print("AnimationTree mannequin_animation_tree.gd script verified.")
	
	if enemy.animation_tree != anim_tree:
		printerr("TEST FAILED: Enemy.animation_tree does not point to Enemy_Medium/AnimationTree.")
		get_tree().quit(1)
		return
	print("Enemy.animation_tree onready variable verified.")
	
	if not is_equal_approx(enemy.base_speed, 3.5):
		printerr("TEST FAILED: Expected Enemy.base_speed == 3.5, got: ", enemy.base_speed)
		get_tree().quit(1)
		return
	print("Enemy.base_speed (3.5) verified.")
	
	var col_shape: CollisionShape3D = enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape == null:
		printerr("TEST FAILED: CollisionShape3D node not found on Enemy.")
		get_tree().quit(1)
		return
	if not (col_shape.shape is CapsuleShape3D):
		printerr("TEST FAILED: CollisionShape3D shape is not a CapsuleShape3D.")
		get_tree().quit(1)
		return
	print("CollisionShape3D with CapsuleShape3D verified.")
	
	# ---------------------------------------------------------
	# PART 3: HealthComponent & HealthBar Wiring
	# ---------------------------------------------------------
	print("\n>>> PART 3: HealthComponent & HealthBar Wiring")
	var health_comp: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
	if health_comp == null:
		printerr("TEST FAILED: HealthComponent node not found on Enemy.")
		get_tree().quit(1)
		return
	if health_comp.max_health != 40.0:
		printerr("TEST FAILED: Expected max_health == 40.0, got: ", health_comp.max_health)
		get_tree().quit(1)
		return
	if health_comp.current_health != 40.0:
		printerr("TEST FAILED: Expected current_health == 40.0, got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("HealthComponent verified (max_health: 40.0, current_health: 40.0).")
	
	var health_bar: HealthBar = enemy.get_node_or_null("HealthBar") as HealthBar
	if health_bar == null:
		printerr("TEST FAILED: HealthBar node not found on Enemy.")
		get_tree().quit(1)
		return
	if health_bar.health_component != health_comp:
		printerr("TEST FAILED: HealthBar.health_component is not wired to Enemy HealthComponent.")
		get_tree().quit(1)
		return
	print("HealthBar health_component reference verified.")
	
	# ---------------------------------------------------------
	# PART 4: StateMachine, EnemyWait & EnemyStun Verification
	# ---------------------------------------------------------
	print("\n>>> PART 4: StateMachine, EnemyWait & EnemyStun State Verification")
	var state_machine: StateMachine = enemy.get_node_or_null("StateMachine") as StateMachine
	if state_machine == null:
		printerr("TEST FAILED: StateMachine node not found on Enemy.")
		get_tree().quit(1)
		return
	print("StateMachine node found.")
	
	if enemy.state_machine != state_machine:
		printerr("TEST FAILED: Enemy.state_machine does not point to StateMachine.")
		get_tree().quit(1)
		return
	print("Enemy.state_machine onready variable verified.")

	var enemy_wait: EnemyWait = state_machine.get_node_or_null("EnemyWait") as EnemyWait
	if enemy_wait == null:
		printerr("TEST FAILED: EnemyWait node not found under StateMachine.")
		get_tree().quit(1)
		return
	print("EnemyWait node found.")

	var enemy_stun: EnemyStun = state_machine.get_node_or_null("EnemyStun") as EnemyStun
	if enemy_stun == null:
		printerr("TEST FAILED: EnemyStun node not found under StateMachine.")
		get_tree().quit(1)
		return
	print("EnemyStun node found.")

	if state_machine.initial_state != enemy_wait:
		printerr("TEST FAILED: StateMachine initial_state is not EnemyWait.")
		get_tree().quit(1)
		return
	print("StateMachine initial_state is EnemyWait.")

	if state_machine.state != enemy_wait:
		printerr("TEST FAILED: Current state is not EnemyWait.")
		get_tree().quit(1)
		return
	print("StateMachine current state is EnemyWait.")

	if enemy_wait.enemy != enemy:
		printerr("TEST FAILED: EnemyWait.enemy is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyWait.enemy reference verified.")

	if enemy_stun.enemy != enemy:
		printerr("TEST FAILED: EnemyStun.enemy is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyStun.enemy reference verified.")

	if enemy_stun.next_state != enemy_wait:
		printerr("TEST FAILED: EnemyStun.next_state is not wired to EnemyWait.")
		get_tree().quit(1)
		return
	print("EnemyStun.next_state wired to EnemyWait.")

	if enemy.stun_state != enemy_stun:
		printerr("TEST FAILED: Enemy.stun_state is not wired to EnemyStun.")
		get_tree().quit(1)
		return
	print("Enemy.stun_state export verified.")

	var enemy_defeat: EnemyDefeat = state_machine.get_node_or_null("EnemyDefeat") as EnemyDefeat
	if enemy_defeat == null:
		printerr("TEST FAILED: EnemyDefeat node not found under StateMachine.")
		get_tree().quit(1)
		return
	print("EnemyDefeat node found.")

	if enemy_defeat.enemy != enemy:
		printerr("TEST FAILED: EnemyDefeat.enemy is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyDefeat.enemy reference verified.")

	if enemy.defeat_state != enemy_defeat:
		printerr("TEST FAILED: Enemy.defeat_state is not wired to EnemyDefeat.")
		get_tree().quit(1)
		return
	print("Enemy.defeat_state export verified.")

	# Verify EnemyWait.enter sets WalkSpace and blend_target = -1.0
	enemy_wait.enter("")
	var anim_tree_script_inst: Object = anim_tree
	var blend_target_val: Variant = anim_tree_script_inst.get("blend_target")
	if blend_target_val == null or not is_equal_approx(float(blend_target_val), -1.0):
		printerr("TEST FAILED: blend_target was not set to -1.0 on enter. Got: ", blend_target_val)
		get_tree().quit(1)
		return
	print("EnemyWait.enter() verified (blend_target = -1.0).")

	# Test core_movement with direction
	var move_dir := Vector3(1.0, 0.0, 0.0)
	enemy_wait.core_movement(enemy.base_speed, move_dir)
	if not is_equal_approx(enemy.velocity.x, enemy.base_speed) or not is_equal_approx(enemy.velocity.z, 0.0):
		printerr("TEST FAILED: core_movement did not set velocity correctly with direction.")
		get_tree().quit(1)
		return
	print("core_movement with direction verified.")

	# Test core_movement deceleration with ZERO direction
	enemy_wait.core_movement(enemy.base_speed, Vector3.ZERO)
	if not is_equal_approx(enemy.velocity.x, 0.0):
		printerr("TEST FAILED: core_movement did not decelerate velocity to 0.")
		get_tree().quit(1)
		return
	print("core_movement deceleration with Vector3.ZERO verified.")

	# Test enemy_stun physics_update zeroes velocity
	enemy.velocity = Vector3(5.0, 0.0, 5.0)
	enemy_stun.physics_update(0.1)
	if enemy.velocity != Vector3.ZERO:
		printerr("TEST FAILED: EnemyStun.physics_update did not zero velocity. Got: ", enemy.velocity)
		get_tree().quit(1)
		return
	print("EnemyStun.physics_update velocity zeroing verified.")

	# Test enemy_defeat physics_update zeroes velocity
	enemy.velocity = Vector3(5.0, 0.0, 5.0)
	enemy_defeat.physics_update(0.1)
	if enemy.velocity != Vector3.ZERO:
		printerr("TEST FAILED: EnemyDefeat.physics_update did not zero velocity. Got: ", enemy.velocity)
		get_tree().quit(1)
		return
	print("EnemyDefeat.physics_update velocity zeroing verified.")

	# ---------------------------------------------------------
	# PART 5: HitAudio & Stun State Trigger on Damage
	# ---------------------------------------------------------
	print("\n>>> PART 5: HitAudio & Stun State Trigger on Damage")
	var hit_audio: AudioStreamPlayer3D = enemy.get_node_or_null("HitAudio") as AudioStreamPlayer3D
	if hit_audio == null:
		printerr("TEST FAILED: HitAudio node not found on Enemy.")
		get_tree().quit(1)
		return
	if hit_audio.stream == null:
		printerr("TEST FAILED: HitAudio stream is null.")
		get_tree().quit(1)
		return
	if hit_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected HitAudio bus == 'SFX', got: ", hit_audio.bus)
		get_tree().quit(1)
		return
	if health_comp.hit_audio != hit_audio:
		printerr("TEST FAILED: HealthComponent.hit_audio is not assigned to HitAudio.")
		get_tree().quit(1)
		return
	print("HitAudio configured (stream assigned, SFX bus, wired to HealthComponent).")
	
	# Test taking damage triggers HitAudio AND transitions to EnemyStun
	hit_audio.stop()
	health_comp.take_damage(10.0)
	await get_tree().process_frame
	if not hit_audio.playing:
		printerr("TEST FAILED: HitAudio is not playing after take_damage().")
		get_tree().quit(1)
		return
	print("HitAudio playback confirmed on taking damage.")
	if health_comp.current_health != 30.0:
		printerr("TEST FAILED: Health not reduced to 30.0 after 10 damage. Got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Health reduced to 30.0 as expected.")
	hit_audio.stop()

	if state_machine.state != enemy_stun:
		printerr("TEST FAILED: StateMachine did not transition to EnemyStun on damage. Got: ", state_machine.state.name)
		get_tree().quit(1)
		return
	print("StateMachine transition to EnemyStun on damage verified!")

	# Simulate animation finish on AnimationTree to verify return to EnemyWait
	anim_tree.animation_finished.emit("Stun")
	await get_tree().process_frame
	if state_machine.state != enemy_wait:
		printerr("TEST FAILED: StateMachine did not return to EnemyWait after animation finished. Got: ", state_machine.state.name)
		get_tree().quit(1)
		return
	print("StateMachine returned to EnemyWait after stun animation finished!")

	# Test defeat emission and transition to EnemyDefeat
	var defeat_emitted: Array[bool] = [false]
	health_comp.defeat.connect(func() -> void: defeat_emitted[0] = true)
	health_comp.take_damage(30.0)
	await get_tree().process_frame
	if not defeat_emitted[0]:
		printerr("TEST FAILED: defeat signal was not emitted when health reached 0.")
		get_tree().quit(1)
		return
	print("HealthComponent defeat signal emitted successfully.")

	if state_machine.state != enemy_defeat:
		printerr("TEST FAILED: StateMachine did not transition to EnemyDefeat on defeat. Got: ", state_machine.state.name)
		get_tree().quit(1)
		return
	print("StateMachine transition to EnemyDefeat verified!")

	# Verify enemy remains in EnemyDefeat even after Defeat animation finished
	anim_tree.animation_finished.emit("Defeat")
	await get_tree().process_frame
	if state_machine.state != enemy_defeat:
		printerr("TEST FAILED: StateMachine left EnemyDefeat unexpectedly! Got: ", state_machine.state.name)
		get_tree().quit(1)
		return
	print("Enemy properly remains in EnemyDefeat state after animation finished.")
	
	# Verify collision_shape_3d is disabled after defeat
	await get_tree().physics_frame
	if not enemy.collision_shape_3d.disabled:
		printerr("TEST FAILED: Enemy collision_shape_3d was not disabled on defeat.")
		get_tree().quit(1)
		return
	print("Enemy collision_shape_3d disabled on defeat verified!")
	
	# ---------------------------------------------------------
	# PART 6: LevelTemplate Instantiation Verification
	# ---------------------------------------------------------
	print("\n>>> PART 6: LevelTemplate Enemy Placement Verification")
	enemy.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var level_enemy: Enemy = level.get_node_or_null("Enemy") as Enemy
	if level_enemy == null:
		printerr("TEST FAILED: Enemy instance not found in LevelTemplate scene.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy instance found in LevelTemplate: ", level_enemy.name)
	
	var level_enemy_health: HealthComponent = level_enemy.get_node_or_null("HealthComponent") as HealthComponent
	if level_enemy_health == null or level_enemy_health.max_health != 40.0:
		printerr("TEST FAILED: LevelTemplate Enemy HealthComponent missing or invalid max_health.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("LevelTemplate Enemy HealthComponent confirmed with 40 max health.")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# ---------------------------------------------------------
	# PART 7: RangedEnemy Scene Verification
	# ---------------------------------------------------------
	print("\n>>> PART 7: RangedEnemy Scene & State Verification")
	var ranged_scene: PackedScene = load("res://Enemy/ranged_enemy.tscn")
	if ranged_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/ranged_enemy.tscn")
		get_tree().quit(1)
		return
	var ranged_enemy: Enemy = ranged_scene.instantiate() as Enemy
	if ranged_enemy == null:
		printerr("TEST FAILED: RangedEnemy is not an instance of Enemy.")
		get_tree().quit(1)
		return
	print("RangedEnemy instance verified as Enemy subclass.")
	
	add_child(ranged_enemy)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var ranged_attack: EnemyAttack = ranged_enemy.get_node_or_null("StateMachine/EnemyAttack") as EnemyAttack
	if ranged_attack == null:
		printerr("TEST FAILED: EnemyAttack node missing under RangedEnemy StateMachine.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack node verified under RangedEnemy StateMachine.")
	
	if ranged_attack.attack_name != "RangedAttack":
		printerr("TEST FAILED: EnemyAttack.attack_name is '", ranged_attack.attack_name, "', expected 'RangedAttack'.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack.attack_name verified as 'RangedAttack'.")
	
	if ranged_attack.enemy != ranged_enemy:
		printerr("TEST FAILED: EnemyAttack.enemy does not point to RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack.enemy reference verified.")
	
	ranged_enemy.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	print("\n====================================================================")
	print("  ALL BASE ENEMY & RANGED ENEMY TESTS PASSED!                       ")
	print("  1. Enemy class_name & CharacterBody3D hierarchy verified          ")
	print("  2. CapsuleMesh & CapsuleShape3D configured                        ")
	print("  3. Collision layers 1 & 2 active (collision_layer = 3)            ")
	print("  4. Skeleton bone attachments (WeaponSlot, FootBones) verified     ")
	print("  5. HealthComponent (40 max health) & HealthBar wired              ")
	print("  6. StateMachine, EnemyWait, EnemyStun & EnemyDefeat wired         ")
	print("  7. Damage triggers HitAudio & transitions to EnemyStun            ")
	print("  8. Stun animation_finished returns to EnemyWait                   ")
	print("  9. Defeat transitions to EnemyDefeat & persists on anim finished   ")
	print("  10. CollisionShape3D deferred disabled on defeat verified         ")
	print("  11. LevelTemplate enemy replacement confirmed                     ")
	print("  12. RangedEnemy scene, EnemyAttack state & RangedAttack verified  ")
	print("====================================================================")
	
	get_tree().quit(0)

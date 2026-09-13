extends Node

const TestUtils = preload("res://test/test_utils.gd")
const UpgradeIcon = preload("res://UserInterface/upgrade_icon.gd")
const UpgradeResource = preload("res://UserInterface/upgrade_resource.gd")

func _ready() -> void:
	print("--- RUNNING BASE ENEMY SCENE & LOGIC TEST ---")
	
	# ---------------------------------------------------------
	# PART 1: Enemy Scene & Class Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Enemy Instantiation & Node Types")
	var enemy_scene: PackedScene = load("res://Enemy/enemy_base.tscn")
	if enemy_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/enemy_base.tscn")
		get_tree().quit(1)
		return
		
	var enemy: Character = enemy_scene.instantiate() as Character
	if enemy == null or not (enemy is Character):
		printerr("TEST FAILED: enemy is not an instance of class_name Character.")
		get_tree().quit(1)
		return
	if not enemy.is_in_group("enemy"):
		printerr("TEST FAILED: enemy is not in group 'enemy'.")
		get_tree().quit(1)
		return
	print("Enemy scene loaded and Character with 'enemy' group verified.")
	
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
	
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100.0, 1.0, 100.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	enemy.position = Vector3(0.0, 1.0, 0.0)
	add_child(enemy)
	enemy.velocity = Vector3(0.0, -1.0, 0.0)
	enemy.move_and_slide()
	
	var nav_agent: NavigationAgent3D = enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav_agent == null:
		printerr("TEST FAILED: NavigationAgent3D node not found on Enemy.")
		get_tree().quit(1)
		return
	if enemy.navigation_agent_3d != nav_agent:
		printerr("TEST FAILED: Enemy.navigation_agent_3d does not point to NavigationAgent3D.")
		get_tree().quit(1)
		return
	print("Enemy NavigationAgent3D node and onready variable verified.")
	
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
	
	if enemy.mesh_mount != anim_anchor:
		printerr("TEST FAILED: Enemy.mesh_mount is not wired to AnimationAnchor.")
		get_tree().quit(1)
		return
	print("Enemy.mesh_mount export verified.")
	
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
	
	if not is_equal_approx(enemy.movement_speed, 3.5):
		printerr("TEST FAILED: Expected Enemy.movement_speed == 3.5, got: ", enemy.movement_speed)
		get_tree().quit(1)
		return
	print("Enemy.movement_speed (3.5) verified.")
	
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
	# PART 4: StateMachine, EnemyMove, EnemyStun & AIStateMachine Verification
	# ---------------------------------------------------------
	print("\n>>> PART 4: StateMachine, EnemyMove, EnemyStun & AIStateMachine Verification")
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
	print("Enemy.state_machine export verified.")

	var enemy_move: EnemyMove = state_machine.get_node_or_null("EnemyMove") as EnemyMove
	if enemy_move == null:
		printerr("TEST FAILED: EnemyMove node not found under StateMachine.")
		get_tree().quit(1)
		return
	print("EnemyMove node found.")

	var enemy_stun: EnemyStun = state_machine.get_node_or_null("EnemyStun") as EnemyStun
	if enemy_stun == null:
		printerr("TEST FAILED: EnemyStun node not found under StateMachine.")
		get_tree().quit(1)
		return
	print("EnemyStun node found.")

	if state_machine.initial_state != enemy_move:
		printerr("TEST FAILED: StateMachine initial_state is not EnemyMove.")
		get_tree().quit(1)
		return
	print("StateMachine initial_state is EnemyMove.")

	if state_machine.state != enemy_move:
		printerr("TEST FAILED: Current state is not EnemyMove.")
		get_tree().quit(1)
		return
	print("StateMachine current state is EnemyMove.")

	if enemy_move.character != enemy:
		printerr("TEST FAILED: EnemyMove.character is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyMove.character reference verified.")

	if enemy_stun.character != enemy:
		printerr("TEST FAILED: EnemyStun.character is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyStun.character reference verified.")

	if enemy_stun.next_state != enemy_move:
		printerr("TEST FAILED: EnemyStun.next_state is not wired to EnemyMove.")
		get_tree().quit(1)
		return
	print("EnemyStun.next_state wired to EnemyMove.")

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

	if enemy_defeat.character != enemy:
		printerr("TEST FAILED: EnemyDefeat.character is not wired to Enemy.")
		get_tree().quit(1)
		return
	print("EnemyDefeat.character reference verified.")

	if enemy.defeat_state != enemy_defeat:
		printerr("TEST FAILED: Enemy.defeat_state is not wired to EnemyDefeat.")
		get_tree().quit(1)
		return
	print("Enemy.defeat_state export verified.")

	# Verify AIStateMachine exists on base enemy (abstract base template; child scenes configure states)
	var ai_sm: AIStateMachine = enemy.ai_state_machine as AIStateMachine
	if ai_sm == null:
		printerr("TEST FAILED: Enemy.ai_state_machine is null or not AIStateMachine.")
		get_tree().quit(1)
		return
	print("Enemy AIStateMachine verified.")

	# Verify EnemyMove.enter sets WalkSpace
	enemy_move.enter("")
	print("EnemyMove.enter() verified.")

	# Test core_movement with direction
	var move_dir := Vector3(1.0, 0.0, 0.0)
	enemy_move.core_movement(0.1, enemy.movement_speed, move_dir)
	if not is_equal_approx(enemy.velocity.x, enemy.movement_speed) or not is_equal_approx(enemy.velocity.z, 0.0):
		printerr("TEST FAILED: core_movement did not set velocity correctly with direction.")
		get_tree().quit(1)
		return
	print("core_movement with direction verified.")

	# Test core_movement deceleration with ZERO direction
	enemy_move.core_movement(0.1, enemy.movement_speed, Vector3.ZERO)
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

	# Simulate animation finish on AnimationTree to verify return to EnemyMove
	anim_tree.animation_finished.emit("Stun")
	await get_tree().process_frame
	if state_machine.state != enemy_move:
		printerr("TEST FAILED: StateMachine did not return to EnemyMove after animation finished. Got: ", state_machine.state.name)
		get_tree().quit(1)
		return
	print("StateMachine returned to EnemyMove after stun animation finished!")

	# Test defeat emission and transition to EnemyDefeat
	var enemy_defeat_emitted: Array[bool] = [false]
	if enemy.has_signal("defeat"):
		enemy.defeat.connect(func() -> void: enemy_defeat_emitted[0] = true)
	var defeat_emitted: Array[bool] = [false]
	health_comp.defeat.connect(func() -> void: defeat_emitted[0] = true)
	health_comp.take_damage(30.0)
	await get_tree().process_frame
	if not enemy_defeat_emitted[0]:
		printerr("TEST FAILED: Enemy defeat signal was not emitted when health reached 0.")
		get_tree().quit(1)
		return
	print("Enemy defeat signal emitted successfully.")
	if not defeat_emitted[0]:
		printerr("TEST FAILED: HealthComponent defeat signal was not emitted when health reached 0.")
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
	floor_body.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# Verify WaveObjective
	var wave_obj: WaveObjective = level.get_node_or_null("WaveObjective") as WaveObjective
	if wave_obj == null:
		printerr("TEST FAILED: WaveObjective node not found in LevelTemplate.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective node verified in LevelTemplate.")
	
	if not wave_obj.has_signal("finished"):
		printerr("TEST FAILED: WaveObjective does not have finished signal.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective finished signal verified.")
	
	if wave_obj.all_enemies.size() != ProgressionState.get_enemy_count():
		printerr("TEST FAILED: WaveObjective all_enemies size is ", wave_obj.all_enemies.size(), ", expected ", ProgressionState.get_enemy_count())
		level.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective all_enemies size (", wave_obj.all_enemies.size(), ") matches ProgressionState.get_enemy_count() verified.")

	# Verify ExitPoint
	var exit_point: ExitPoint = level.get_node_or_null("ExitPoint") as ExitPoint
	if exit_point == null:
		printerr("TEST FAILED: ExitPoint node not found in LevelTemplate.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint node verified in LevelTemplate.")

	if exit_point.visible:
		printerr("TEST FAILED: ExitPoint should be invisible initially (_ready visible = false).")
		level.queue_free()
		get_tree().quit(1)
		return
	if not exit_point.locked:
		printerr("TEST FAILED: ExitPoint should be locked initially.")
		level.queue_free()
		get_tree().quit(1)
		return
	var valid_paths: Array[String] = ["res://Levels/level_template.tscn", "res://Levels/LevelTemplate.tscn", "uid://dyj3auoai18wd", ""]
	if not exit_point.next_scene_path in valid_paths or not exit_point.next_level_path in valid_paths:
		printerr("TEST FAILED: ExitPoint next_scene_path: '", exit_point.next_scene_path, "', next_level_path: '", exit_point.next_level_path, "'")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint initially invisible, locked, and next_scene_path export var verified.")

	# Verify difficulty curve and ProgressionState enemy count
	var curve_res: Curve = load("res://Singletons/difficulty_curve.tres") as Curve
	if curve_res == null or curve_res.point_count < 2:
		printerr("TEST FAILED: difficulty_curve.tres missing or invalid point count.")
		level.queue_free()
		get_tree().quit(1)
		return
	if ProgressionState.get_enemy_count() < 3:
		printerr("TEST FAILED: ProgressionState.get_enemy_count() at level 1 is ", ProgressionState.get_enemy_count(), ", expected >= 3.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Difficulty curve and ProgressionState.get_enemy_count() (level 1: ", ProgressionState.get_enemy_count(), ") verified.")

	# Verify ExitPoint Area3D & CollisionShape3D
	var exit_area: Area3D = exit_point.get_node_or_null("Area3D") as Area3D
	if exit_area == null:
		printerr("TEST FAILED: ExitPoint missing Area3D child.")
		level.queue_free()
		get_tree().quit(1)
		return
	var exit_col: CollisionShape3D = exit_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if exit_col == null or not (exit_col.shape is SphereShape3D) or (exit_col.shape as SphereShape3D).radius != 2.0:
		printerr("TEST FAILED: ExitPoint Area3D missing SphereShape3D with radius 2.0.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint Area3D and SphereShape3D (radius 2.0) verified.")
	if exit_area.collision_layer != 32 or exit_area.collision_mask != 1:
		printerr("TEST FAILED: ExitPoint Area3D must sit on trigger layer 6 only (layer 32, mask 1). Got layer ", exit_area.collision_layer, " mask ", exit_area.collision_mask)
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint Area3D trigger-layer isolation verified (layer 32, mask 1).")

	# Projectiles must ignore the exit trigger: no detonation, no FireballHit.
	var exit_scene: PackedScene = load("res://Levels/exit_point.tscn") as PackedScene
	var exit_instance: Node3D = exit_scene.instantiate() as Node3D
	add_child(exit_instance)
	exit_instance.global_position = Vector3(0.0, 1.0, 50.0)
	var exit_proj_scene: PackedScene = load("res://Enemy/enemy_projectile.tscn") as PackedScene
	var exit_proj: EnemyProjectile = exit_proj_scene.instantiate() as EnemyProjectile
	add_child(exit_proj)
	exit_proj.global_position = Vector3(0.0, 1.0, 50.0)
	var fireball_ids_before: Array[int] = []
	for c: Node in get_tree().current_scene.get_children():
		if c.name.begins_with("FireballHit"):
			fireball_ids_before.append(c.get_instance_id())
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var exit_detonated := false
	for c: Node in get_tree().current_scene.get_children():
		if c.name.begins_with("FireballHit") and not fireball_ids_before.has(c.get_instance_id()):
			exit_detonated = true
			break
	if exit_proj.is_queued_for_deletion() or exit_detonated:
		printerr("TEST FAILED: Projectile detonated on ExitPoint trigger.")
		exit_instance.queue_free()
		if not exit_proj.is_queued_for_deletion():
			exit_proj.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	print("Projectile ignores ExitPoint trigger verified (no detonation).")
	exit_instance.queue_free()
	exit_proj.queue_free()
	await get_tree().physics_frame

	# Verify ExitPoint WispMesh & ShaderMaterial (Lecture 73)
	var wisp_mesh: MeshInstance3D = exit_point.get_node_or_null("WispMesh") as MeshInstance3D
	if wisp_mesh == null:
		printerr("TEST FAILED: ExitPoint missing WispMesh child.")
		level.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(wisp_mesh.position.y, 10.0) or wisp_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		printerr("TEST FAILED: WispMesh position or cast_shadow invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var cyl_mesh: CylinderMesh = wisp_mesh.mesh as CylinderMesh
	if cyl_mesh == null or not is_equal_approx(cyl_mesh.top_radius, 2.0) or not is_equal_approx(cyl_mesh.bottom_radius, 2.0) or not is_equal_approx(cyl_mesh.height, 20.0) or cyl_mesh.cap_top or cyl_mesh.cap_bottom:
		printerr("TEST FAILED: WispMesh CylinderMesh configuration invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var wisp_mat: ShaderMaterial = wisp_mesh.material_override as ShaderMaterial
	if wisp_mat == null or wisp_mat.shader == null:
		printerr("TEST FAILED: WispMesh ShaderMaterial or shader invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var cutoff_val: Variant = wisp_mat.get_shader_parameter("Cuttoff")
	if cutoff_val == null or not is_equal_approx(float(cutoff_val), 0.41):
		printerr("TEST FAILED: WispMesh shader Cuttoff expected 0.41, got: ", cutoff_val)
		level.queue_free()
		get_tree().quit(1)
		return
	if not (wisp_mat.get_shader_parameter("GradientParam") is GradientTexture2D) or not (wisp_mat.get_shader_parameter("NoiseParam") is NoiseTexture2D):
		printerr("TEST FAILED: WispMesh shader GradientParam or NoiseParam invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint WispMesh (CylinderMesh & ShaderMaterial) verified.")

	# Verify ExitPoint AnimationPlayer & GPUParticles3D (Lecture 74)
	var exit_anim: AnimationPlayer = exit_point.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if exit_anim == null or exit_point.animation_player != exit_anim:
		printerr("TEST FAILED: ExitPoint AnimationPlayer node missing or onready var not wired.")
		level.queue_free()
		get_tree().quit(1)
		return
	if not exit_anim.has_animation(&"Exit") or not exit_anim.has_animation(&"RESET"):
		printerr("TEST FAILED: ExitPoint AnimationPlayer missing Exit or RESET animation.")
		level.queue_free()
		get_tree().quit(1)
		return
	var exit_torus_particles: GPUParticles3D = exit_point.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if exit_torus_particles == null:
		printerr("TEST FAILED: ExitPoint GPUParticles3D missing.")
		level.queue_free()
		get_tree().quit(1)
		return
	if not exit_torus_particles.one_shot or not is_equal_approx(exit_torus_particles.lifetime, 3.0) or not is_equal_approx(exit_torus_particles.preprocess, 1.0):
		printerr("TEST FAILED: ExitPoint GPUParticles3D lifetime/one_shot/preprocess invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var torus_mesh: TorusMesh = exit_torus_particles.draw_pass_1 as TorusMesh
	if torus_mesh == null or not is_equal_approx(torus_mesh.inner_radius, 0.9):
		printerr("TEST FAILED: ExitPoint TorusMesh draw pass or inner_radius invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var torus_mat: StandardMaterial3D = exit_torus_particles.material_override as StandardMaterial3D
	if torus_mat == null or torus_mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA or torus_mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or not torus_mat.vertex_color_use_as_albedo:
		printerr("TEST FAILED: ExitPoint TorusMesh material_override invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	var torus_proc_mat: ParticleProcessMaterial = exit_torus_particles.process_material as ParticleProcessMaterial
	if torus_proc_mat == null or torus_proc_mat.gravity != Vector3.ZERO or not is_equal_approx(torus_proc_mat.scale_min, 5.0) or not is_equal_approx(torus_proc_mat.scale_max, 5.0):
		printerr("TEST FAILED: ExitPoint TorusMesh process_material gravity/scale invalid.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint AnimationPlayer and Torus GPUParticles3D verified.")

	var is_connected_to_unlock := false
	for conn: Dictionary in wave_obj.finished.get_connections():
		if conn["callable"].get_object() == exit_point and conn["callable"].get_method() == "unlock":
			is_connected_to_unlock = true
			break
	if not is_connected_to_unlock:
		printerr("TEST FAILED: WaveObjective.finished is not connected to ExitPoint.unlock().")
		level.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective.finished -> ExitPoint.unlock() connection verified.")

	exit_point.unlock()
	if not exit_point.visible:
		printerr("TEST FAILED: ExitPoint.unlock() did not set visible = true.")
		level.queue_free()
		get_tree().quit(1)
		return
	if exit_point.locked:
		printerr("TEST FAILED: ExitPoint.unlock() did not set locked = false.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint.unlock() (visible = true, locked = false) verified.")
	exit_point.visible = false
	exit_point.locked = true

	# Verify SceneTransition autoload
	var scene_trans: Node = get_node_or_null("/root/SceneTransition")
	if scene_trans == null or not (scene_trans is CanvasLayer):
		printerr("TEST FAILED: SceneTransition autoload not found as CanvasLayer under /root.")
		level.queue_free()
		get_tree().quit(1)
		return
	var trans_rect: ColorRect = scene_trans.get_node_or_null("ColorRect") as ColorRect
	if trans_rect == null or trans_rect.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: SceneTransition ColorRect missing or mouse_filter not IGNORE.")
		level.queue_free()
		get_tree().quit(1)
		return
	if not scene_trans.has_method("fade_in") or not scene_trans.has_method("fade_out") or not scene_trans.has_method("load_scene_path") or not scene_trans.has_method("load_next_level"):
		printerr("TEST FAILED: SceneTransition missing fade_in/fade_out/load_scene_path/load_next_level methods.")
		level.queue_free()
		get_tree().quit(1)
		return
	if not ("levels" in scene_trans) or (scene_trans.get("levels") as Array).size() != 3:
		printerr("TEST FAILED: SceneTransition levels array missing or size != 3.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("SceneTransition autoload, ColorRect, levels array (size 3) & load_next_level verified.")

	# Verify SceneTransition.player_cache property
	if not ("player_cache" in scene_trans):
		printerr("TEST FAILED: SceneTransition missing player_cache property.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("SceneTransition player_cache property verified.")

	# Verify LevelTemplate player replacement via player_cache
	var cached_player_scene: PackedScene = preload("res://Player/player.tscn")
	var cached_player: Character = cached_player_scene.instantiate() as Character
	scene_trans.add_child(cached_player)
	cached_player.process_mode = Node.PROCESS_MODE_DISABLED
	cached_player.health_component.current_health = 42.0
	scene_trans.player_cache = cached_player

	var test_level: Node3D = level_scene.instantiate() as Node3D
	add_child(test_level)
	if test_level.get("player") != cached_player or cached_player.get_parent() != test_level:
		printerr("TEST FAILED: LevelTemplate did not reparent and assign cached player.")
		test_level.queue_free()
		cached_player.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	if cached_player.process_mode != Node.PROCESS_MODE_INHERIT:
		printerr("TEST FAILED: LevelTemplate did not restore cached player process_mode to INHERIT.")
		test_level.queue_free()
		cached_player.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	if cached_player.health_component.current_health != 42.0:
		printerr("TEST FAILED: Cached player health was not preserved across level load.")
		test_level.queue_free()
		cached_player.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	if cached_player.global_position != Vector3(4, 1, 0):
		printerr("TEST FAILED: Cached player position (", cached_player.global_position, ") not matched to template spawn position (4, 1, 0).")
		test_level.queue_free()
		cached_player.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	print("LevelTemplate player state preservation (health, position, process_mode) verified.")
	scene_trans.player_cache = null
	test_level.queue_free()

	var level_enemy: Character = TestUtils.find_enemy(level)
	if level_enemy == null or not level_enemy.is_in_group("enemy"):
		printerr("TEST FAILED: No enemy Character instance found via TestUtils in LevelTemplate scene.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy instance found in LevelTemplate via WaveObjective: ", level_enemy.name)
	
	var level_enemy_health: HealthComponent = level_enemy.get_node_or_null("HealthComponent") as HealthComponent
	if level_enemy_health == null or not (level_enemy_health.max_health in [40.0, 55.0, 60.0, 70.0, 100.0]):
		printerr("TEST FAILED: LevelTemplate Enemy HealthComponent missing or invalid max_health.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("LevelTemplate Enemy HealthComponent confirmed with ", level_enemy_health.max_health, " max health.")

	var nav_region: NavigationRegion3D = level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D

	if nav_region == null:
		printerr("TEST FAILED: NavigationRegion3D node not found in LevelTemplate.")
		level.queue_free()
		get_tree().quit(1)
		return
	if nav_region.navigation_mesh == null:
		printerr("TEST FAILED: NavigationRegion3D navigation_mesh is null.")
		level.queue_free()
		get_tree().quit(1)
		return
	if nav_region.navigation_mesh.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
		printerr("TEST FAILED: NavigationMesh parsed_geometry_type is not Static Colliders.")
		level.queue_free()
		get_tree().quit(1)
		return
	if nav_region.navigation_mesh.get_polygon_count() == 0 or nav_region.navigation_mesh.get_vertices().is_empty():
		printerr("TEST FAILED: NavigationMesh has no baked polygons or vertices.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("LevelTemplate NavigationRegion3D & NavigationMesh (Static Colliders, ", nav_region.navigation_mesh.get_polygon_count(), " polygons) verified.")

	# Verify Level 1 scene
	var level_1_scene: PackedScene = load("res://Levels/level_1.tscn")
	if level_1_scene == null:
		printerr("TEST FAILED: Could not load res://Levels/level_1.tscn")
		level.queue_free()
		get_tree().quit(1)
		return
	var l1: Node3D = level_1_scene.instantiate() as Node3D
	var l1_player: Node3D = l1.get_node_or_null("Player") as Node3D
	if l1_player == null or l1_player.transform.origin != Vector3(4, 1, -4):
		printerr("TEST FAILED: Level 1 Player spawn position is not (4, 1, -4): ", l1_player.transform.origin if l1_player else "null")
		l1.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l1_exit: Node3D = l1.get_node_or_null("ExitPoint") as Node3D
	if l1_exit == null or l1_exit.transform.origin != Vector3(-8, 0, -4):
		printerr("TEST FAILED: Level 1 ExitPoint position is not (-8, 0, -4): ", l1_exit.transform.origin if l1_exit else "null")
		l1.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l1_nav: NavigationRegion3D = l1.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if l1_nav == null or l1_nav.navigation_mesh == null or l1_nav.navigation_mesh.get_polygon_count() != 6:
		printerr("TEST FAILED: Level 1 NavigationMesh missing or invalid polygon count.")
		l1.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l1_vgi: VoxelGI = l1.get_node_or_null("VoxelGI") as VoxelGI
	if l1_vgi == null or l1_vgi.data == null:
		printerr("TEST FAILED: Level 1 VoxelGI missing or data is null.")
		l1.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	print("Level 1 scene (NavMesh 6 polygons, VoxelGI, Player at (4, 1, -4), ExitPoint at (-8, 0, -4)) verified.")
	l1.queue_free()

	# Verify Level 2 scene
	var level_2_scene: PackedScene = load("res://Levels/level_2.tscn")
	if level_2_scene == null:
		printerr("TEST FAILED: Could not load res://Levels/level_2.tscn")
		level.queue_free()
		get_tree().quit(1)
		return
	var l2: Node3D = level_2_scene.instantiate() as Node3D
	var l2_exit: Node3D = l2.get_node_or_null("ExitPoint") as Node3D
	if l2_exit == null or l2_exit.transform.origin != Vector3(-12, 0, -28):
		printerr("TEST FAILED: Level 2 ExitPoint position is not (-12, 0, -28): ", l2_exit.transform.origin if l2_exit else "null")
		l2.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l2_pit2: Node3D = l2.get_node_or_null("Pit2") as Node3D
	if l2_pit2 == null:
		printerr("TEST FAILED: Level 2 Pit2 mesh missing.")
		l2.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l2_nav: NavigationRegion3D = l2.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if l2_nav == null or l2_nav.navigation_mesh == null or l2_nav.navigation_mesh.get_polygon_count() == 0:
		printerr("TEST FAILED: Level 2 NavigationMesh missing or empty.")
		l2.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l2_litter: Node3D = l2_nav.get_node_or_null("Litter") as Node3D
	if l2_litter == null or l2_litter.get_child_count() == 0:
		printerr("TEST FAILED: Level 2 Litter node missing or empty under NavigationRegion3D.")
		l2.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l2_vgi: VoxelGI = l2.get_node_or_null("VoxelGI") as VoxelGI
	if l2_vgi == null or l2_vgi.data == null:
		printerr("TEST FAILED: Level 2 VoxelGI missing or data is null.")
		l2.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	print("Level 2 scene (Litter, Pit2, NavMesh, VoxelGI, ExitPoint at (-12, 0, -28)) verified.")
	l2.queue_free()

	# Verify Level 3 scene
	var level_3_scene: PackedScene = load("res://Levels/level_3.tscn")
	if level_3_scene == null:
		printerr("TEST FAILED: Could not load res://Levels/level_3.tscn")
		level.queue_free()
		get_tree().quit(1)
		return
	var l3: Node3D = level_3_scene.instantiate() as Node3D
	var l3_player: Node3D = l3.get_node_or_null("Player") as Node3D
	if l3_player == null or not l3_player.transform.origin.is_equal_approx(Vector3(6.2296762, 1, -2.4801493)):
		printerr("TEST FAILED: Level 3 Player spawn position invalid: ", l3_player.transform.origin if l3_player else "null")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l3_exit: Node3D = l3.get_node_or_null("ExitPoint") as Node3D
	if l3_exit == null or not l3_exit.transform.origin.is_equal_approx(Vector3(3.8668923, 0, -16)):
		printerr("TEST FAILED: Level 3 ExitPoint position is not (3.8668923, 0, -16): ", l3_exit.transform.origin if l3_exit else "null")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l3_pit2: Node3D = l3.get_node_or_null("Pit2") as Node3D
	var l3_pit3: Node3D = l3.get_node_or_null("Pit3") as Node3D
	var l3_pit4: Node3D = l3.get_node_or_null("Pit4") as Node3D
	if l3_pit2 == null or l3_pit3 == null or l3_pit4 == null:
		printerr("TEST FAILED: Level 3 pits (Pit2, Pit3, Pit4) missing.")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l3_nav: NavigationRegion3D = l3.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if l3_nav == null or l3_nav.navigation_mesh == null or l3_nav.navigation_mesh.get_polygon_count() == 0:
		printerr("TEST FAILED: Level 3 NavigationMesh missing or empty.")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l3_litter: Node3D = l3_nav.get_node_or_null("Litter") as Node3D
	if l3_litter == null or l3_litter.get_child_count() == 0:
		printerr("TEST FAILED: Level 3 Litter node missing or empty under NavigationRegion3D.")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var has_flag: bool = false
	for child: Node in l3_litter.get_children():
		if "Flag" in child.name:
			has_flag = true
			break
	if not has_flag:
		printerr("TEST FAILED: Level 3 Litter does not contain Flag prop.")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	var l3_vgi: VoxelGI = l3.get_node_or_null("VoxelGI") as VoxelGI
	if l3_vgi == null or l3_vgi.data == null:
		printerr("TEST FAILED: Level 3 VoxelGI missing or data is null.")
		l3.queue_free()
		level.queue_free()
		get_tree().quit(1)
		return
	print("Level 3 scene (Litter with Flags, Pit2-4, NavMesh, VoxelGI, Player, ExitPoint) verified.")
	l3.queue_free()

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
	var ranged_enemy: Character = ranged_scene.instantiate() as Character
	if ranged_enemy == null or not (ranged_enemy is Character) or not ranged_enemy.is_in_group("enemy"):
		printerr("TEST FAILED: RangedEnemy is not a Character instance in group 'enemy'.")
		get_tree().quit(1)
		return
	print("RangedEnemy instance verified as Character subclass in group 'enemy'.")
	
	var ranged_floor := StaticBody3D.new()
	var rf_col := CollisionShape3D.new()
	var rf_box := BoxShape3D.new()
	rf_box.size = Vector3(20.0, 1.0, 20.0)
	rf_col.shape = rf_box
	rf_col.position = Vector3(0.0, -0.5, 0.0)
	ranged_floor.add_child(rf_col)
	add_child(ranged_floor)

	ranged_enemy.position = Vector3(0.0, 1.0, 0.0)
	add_child(ranged_enemy)
	ranged_enemy.velocity = Vector3(0.0, -1.0, 0.0)
	ranged_enemy.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var ranged_attack: CharacterAttack = ranged_enemy.get_node_or_null("StateMachine/EnemyAttack") as CharacterAttack
	if ranged_attack == null:
		printerr("TEST FAILED: EnemyAttack node missing under RangedEnemy StateMachine.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack node verified under RangedEnemy StateMachine.")
	
	if ranged_attack.attack_animation_name != "RangedAttack":
		printerr("TEST FAILED: EnemyAttack.attack_animation_name is '", ranged_attack.attack_animation_name, "', expected 'RangedAttack'.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack.attack_animation_name verified as 'RangedAttack'.")
	
	if ranged_attack.character != ranged_enemy:
		printerr("TEST FAILED: EnemyAttack.character does not point to RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack.character reference verified.")

	var spawner: ProjectileSpawnerComponent = ranged_enemy.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent missing on RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if spawner.character != ranged_enemy:
		printerr("TEST FAILED: ProjectileSpawnerComponent.character does not point to RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("ProjectileSpawnerComponent verified on RangedEnemy.")

	var ranged_sm: StateMachine = ranged_enemy.get_node_or_null("StateMachine") as StateMachine
	var ranged_move: EnemyMove = ranged_sm.get_node_or_null("EnemyMove") as EnemyMove
	if ranged_move == null or ranged_sm.initial_state != ranged_move:
		printerr("TEST FAILED: RangedEnemy StateMachine initial_state is not EnemyMove.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy StateMachine initial_state is EnemyMove.")

	var ranged_ai_sm: AIStateMachine = ranged_enemy.ai_state_machine as AIStateMachine
	if ranged_ai_sm == null:
		printerr("TEST FAILED: RangedEnemy AIStateMachine missing.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	
	var ranged_meander: AIMeander = ranged_ai_sm.get_node_or_null("AIMeander") as AIMeander
	var ranged_wait: AIWait = ranged_ai_sm.get_node_or_null("AIWait") as AIWait
	var ranged_ai_attack: AIAttack = ranged_ai_sm.get_node_or_null("AIAttack") as AIAttack
	if ranged_meander == null or ranged_wait == null or ranged_ai_attack == null:
		printerr("TEST FAILED: AI states missing under RangedEnemy AIStateMachine (AIMeander, AIWait, AIAttack).")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ranged_ai_sm.initial_state != ranged_meander:
		printerr("TEST FAILED: RangedEnemy AIStateMachine initial_state is not AIMeander.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ranged_meander.attack_state != ranged_ai_attack or not is_equal_approx(ranged_meander.attack_range, 4.0):
		printerr("TEST FAILED: AIMeander attack_state or attack_range mismatch (expected AIAttack and 4.0).")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ranged_wait.next_state != ranged_ai_attack or not is_equal_approx(ranged_wait.wait_duration, 3.0):
		printerr("TEST FAILED: AIWait next_state or wait_duration mismatch (expected AIAttack and 3.0s).")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ranged_ai_attack.attack_state_name != "EnemyAttack" or not is_equal_approx(ranged_ai_attack.cooldown, 3.0) or ranged_ai_attack.next_states.size() != 2 or not ranged_ai_attack.next_states.has(ranged_wait) or not ranged_ai_attack.next_states.has(ranged_meander):
		printerr("TEST FAILED: AIAttack configuration mismatch (expected [AIWait, AIMeander] and cooldown 3.0s).")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy AIStateMachine (AIMeander, AIWait, AIAttack) configuration verified.")
	
	# Verify target acquisition and proximity attack trigger
	var test_player_inst: Character = load("res://Player/player.tscn").instantiate() as Character
	add_child(test_player_inst)
	ranged_enemy.global_position = Vector3.ZERO
	test_player_inst.global_position = Vector3(3.0, 0.0, 0.0)
	
	var resolved_target: Character = ranged_ai_sm.get_target()
	if resolved_target != test_player_inst:
		printerr("TEST FAILED: AIStateMachine.get_target() did not resolve player from group.")
		test_player_inst.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine target acquisition from 'player' group verified.")

	ranged_meander.physics_update(0.016)
	await get_tree().process_frame
	if ranged_ai_sm.state != ranged_ai_attack:
		printerr("TEST FAILED: AIMeander did not transition AIStateMachine to AIAttack on proximity. Got: ", ranged_ai_sm.state.name if ranged_ai_sm.state else "null")
		test_player_inst.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ranged_sm.state != ranged_attack:
		printerr("TEST FAILED: AIAttack did not transition body StateMachine to EnemyAttack. Got: ", ranged_sm.state.name if ranged_sm.state else "null")
		test_player_inst.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIMeander -> AIAttack -> EnemyAttack proximity attack trigger verified.")
	test_player_inst.queue_free()

	# Verify EnemyAttack transitions back to EnemyMove via finish_attack
	ranged_attack.finish_attack("RangedAttack")
	await get_tree().process_frame
	if ranged_sm.state != ranged_move:
		printerr("TEST FAILED: finish_attack() did not transition RangedEnemy back to EnemyMove. Got: ", ranged_sm.state.name if ranged_sm.state else "null")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy transitioned to EnemyMove successfully via finish_attack()!")
	
	ranged_enemy.queue_free()
	ranged_floor.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# ---------------------------------------------------------
	# ---------------------------------------------------------
	# PART 8: Enemy Projectile Scene & Properties
	# ---------------------------------------------------------
	print("\n>>> PART 8: Enemy Projectile Scene & Properties Verification")
	var proj_scene: PackedScene = load("res://Enemy/enemy_projectile.tscn")
	if proj_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/enemy_projectile.tscn")
		get_tree().quit(1)
		return
	var proj: EnemyProjectile = proj_scene.instantiate() as EnemyProjectile
	if proj == null:
		printerr("TEST FAILED: EnemyProjectile is not an instance of EnemyProjectile.")
		get_tree().quit(1)
		return
	if not proj.top_level:
		printerr("TEST FAILED: EnemyProjectile top_level is false.")
		get_tree().quit(1)
		return
	if proj.physics_interpolation_mode != Node3D.PHYSICS_INTERPOLATION_MODE_ON:
		printerr("TEST FAILED: EnemyProjectile physics interpolation is off; movement steps at physics rate.")
		get_tree().quit(1)
		return
	print("EnemyProjectile physics interpolation enabled (smooth render-rate motion).")
	var proj_audio: AudioStreamPlayer3D = proj.get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if proj_audio == null or not proj_audio.autoplay or proj_audio.bus != &"SFX":
		printerr("TEST FAILED: EnemyProjectile AudioStreamPlayer3D improperly configured.")
		get_tree().quit(1)
		return
	print("EnemyProjectile scene & audio verified.")

	# Visual effects verification (Lecture 71)
	if proj.get_node_or_null("MeshInstance3D") != null:
		printerr("TEST FAILED: Placeholder MeshInstance3D should be removed from EnemyProjectile.")
		get_tree().quit(1)
		return
	var particles: GPUParticles3D = proj.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if particles == null:
		printerr("TEST FAILED: GPUParticles3D not found on EnemyProjectile.")
		get_tree().quit(1)
		return
	if particles.amount != 16 or not is_equal_approx(particles.lifetime, 0.25):
		printerr("TEST FAILED: GPUParticles3D amount or lifetime invalid.")
		get_tree().quit(1)
		return
	if not (particles.draw_pass_1 is SphereMesh):
		printerr("TEST FAILED: GPUParticles3D draw_pass_1 is not SphereMesh.")
		get_tree().quit(1)
		return
	var mat_override: StandardMaterial3D = particles.material_override as StandardMaterial3D
	if mat_override == null or mat_override.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or not mat_override.vertex_color_use_as_albedo:
		printerr("TEST FAILED: GPUParticles3D material_override invalid.")
		get_tree().quit(1)
		return
	var proc_mat: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if proc_mat == null or proc_mat.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_SPHERE or not is_equal_approx(proc_mat.emission_sphere_radius, 0.25):
		printerr("TEST FAILED: GPUParticles3D process_material emission shape invalid.")
		get_tree().quit(1)
		return
	if proc_mat.gravity != Vector3(0, 1, 0) or not is_equal_approx(proc_mat.scale_min, 0.25) or not is_equal_approx(proc_mat.scale_max, 0.5):
		printerr("TEST FAILED: GPUParticles3D process_material gravity/scale invalid.")
		get_tree().quit(1)
		return
	if not (proc_mat.scale_curve is CurveTexture) or not (proc_mat.color_ramp is GradientTexture1D):
		printerr("TEST FAILED: GPUParticles3D scale_curve or color_ramp invalid.")
		get_tree().quit(1)
		return
	print("EnemyProjectile visual effects (GPUParticles3D) verified.")

	# Verify FireballHit scene (Lecture 72)
	var hit_scene: PackedScene = load("res://Enemy/fireball_hit.tscn")
	if hit_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/fireball_hit.tscn")
		get_tree().quit(1)
		return
	var hit_instance: Node3D = hit_scene.instantiate() as Node3D
	if hit_instance == null or not hit_instance.top_level:
		printerr("TEST FAILED: FireballHit scene invalid or not top_level.")
		get_tree().quit(1)
		return
	var hit_particles: GPUParticles3D = hit_instance.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if hit_particles == null or not hit_particles.one_shot or not is_equal_approx(hit_particles.explosiveness, 1.0) or not is_equal_approx(hit_particles.lifetime, 0.6):
		printerr("TEST FAILED: FireballHit GPUParticles3D configuration invalid.")
		get_tree().quit(1)
		return
	var fireball_audio: AudioStreamPlayer3D = hit_instance.get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if fireball_audio == null or fireball_audio.stream == null or fireball_audio.bus != &"SFX":
		printerr("TEST FAILED: FireballHit AudioStreamPlayer3D configuration invalid.")
		get_tree().quit(1)
		return
	var hit_anim: AnimationPlayer = hit_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if hit_anim == null or hit_anim.autoplay != &"hit" or not hit_anim.has_animation(&"hit"):
		printerr("TEST FAILED: FireballHit AnimationPlayer configuration invalid.")
		get_tree().quit(1)
		return
	var anim: Animation = hit_anim.get_animation(&"hit")
	if anim == null or anim.get_track_count() != 3:
		printerr("TEST FAILED: FireballHit 'hit' animation track count expected 3, got: ", anim.get_track_count() if anim else 0)
		get_tree().quit(1)
		return
	hit_instance.queue_free()
	print("FireballHit scene (GPUParticles3D, AudioStreamPlayer3D, AnimationPlayer) verified.")

	if not is_equal_approx(proj.speed, 8.0):
		printerr("TEST FAILED: EnemyProjectile.speed expected 8.0, got: ", proj.speed)
		get_tree().quit(1)
		return
	if not is_equal_approx(proj.damage, 5.0):
		printerr("TEST FAILED: EnemyProjectile.damage expected 5.0, got: ", proj.damage)
		get_tree().quit(1)
		return
	print("EnemyProjectile speed (8.0) and damage (5.0) exports verified.")

	var timer: Timer = proj.get_node_or_null("Timer") as Timer
	if timer == null:
		printerr("TEST FAILED: Timer node not found in EnemyProjectile.")
		get_tree().quit(1)
		return
	if not is_equal_approx(timer.wait_time, 10.0) or not timer.autostart:
		printerr("TEST FAILED: EnemyProjectile Timer configuration invalid (wait_time: ", timer.wait_time, ", autostart: ", timer.autostart, ")")
		get_tree().quit(1)
		return
	if not timer.timeout.is_connected(proj._on_timer_timeout):
		printerr("TEST FAILED: EnemyProjectile Timer timeout signal is not connected to _on_timer_timeout.")
		get_tree().quit(1)
		return
	print("EnemyProjectile Timer (10s autostart -> _on_timer_timeout) verified.")

	add_child(proj)
	var attack_comp_proj: AttackComponent = proj.get_node_or_null("AttackComponent") as AttackComponent
	if attack_comp_proj == null:
		printerr("TEST FAILED: AttackComponent not found in EnemyProjectile.")
		proj.queue_free()
		get_tree().quit(1)
		return
	if proj.attack_component != attack_comp_proj:
		printerr("TEST FAILED: EnemyProjectile.attack_component onready var not wired.")
		proj.queue_free()
		get_tree().quit(1)
		return
	print("EnemyProjectile AttackComponent verified.")

	# Test timeout queue_free
	proj._on_timer_timeout()
	if not proj.is_queued_for_deletion():
		printerr("TEST FAILED: _on_timer_timeout did not queue projectile for deletion.")
		proj.queue_free()
		get_tree().quit(1)
		return
	print("EnemyProjectile _on_timer_timeout calls queue_free() verified.")
	proj.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

	# Test projectile movement in physics process
	var proj_move: EnemyProjectile = proj_scene.instantiate() as EnemyProjectile
	add_child(proj_move)
	proj_move.global_position = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	if proj_move.global_position.z <= 0.0:
		printerr("TEST FAILED: EnemyProjectile did not move along positive Z. Position: ", proj_move.global_position)
		proj_move.queue_free()
		get_tree().quit(1)
		return
	print("EnemyProjectile physics movement verified. Moved forward to: ", proj_move.global_position)
	proj_move.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 9: Aiming, Projectile Impact & Damage Verification
	# ---------------------------------------------------------
	print("\n>>> PART 9: Aiming, Projectile Impact & Damage Verification")

	# Verify Player group
	var player_scene: PackedScene = load("res://Player/player.tscn")
	if player_scene == null:
		printerr("TEST FAILED: Could not load res://Player/player.tscn")
		get_tree().quit(1)
		return
	var test_player: Character = player_scene.instantiate() as Character
	if not test_player.is_in_group("player"):
		printerr("TEST FAILED: Player is not in group 'player'.")
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("Player group 'player' verified.")

	# Add player to tree at an offset position (e.g. at (5, 0, 0))
	add_child(test_player)
	test_player.global_position = Vector3(5.0, 0.0, 0.0)

	var shooter: Character = ranged_scene.instantiate() as Character
	add_child(shooter)
	shooter.global_position = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().process_frame

	var resolved_shooter_target: Character = shooter.get_nearest_target("player")
	if resolved_shooter_target != test_player:
		printerr("TEST FAILED: shooter did not resolve test_player from group 'player'.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("shooter successfully found Player via group.")

	var spawner_comp: ProjectileSpawnerComponent = shooter.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner_comp == null or spawner_comp.spawn_point == null:
		printerr("TEST FAILED: RangedEnemy ProjectileSpawnerComponent or spawn_point is null.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy spawn_point assigned: ", spawner_comp.spawn_point.name)

	# Test look_at_target
	shooter.look_at_target(test_player.global_position)
	# The enemy mesh_mount should now face towards the player
	# With use_model_front = true, mesh_mount +Z basis points towards the target
	var facing_dir: Vector3 = shooter.mesh_mount.global_transform.basis.z.normalized()
	var expected_dir: Vector3 = (test_player.global_position - shooter.mesh_mount.global_position)
	expected_dir.y = 0.0
	expected_dir = expected_dir.normalized()
	if facing_dir.dot(expected_dir) < 0.999:
		printerr("TEST FAILED: mesh_mount does not face player. Facing: ", facing_dir, " Expected: ", expected_dir)
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("look_at_target oriented mesh_mount towards player (dot: ", facing_dir.dot(expected_dir), ") verified.")

	# Test projectile spawned matches mesh_mount global_rotation.y
	spawner_comp.spawn_projectile()
	var spawned_proj: EnemyProjectile = null
	for c: Node in get_tree().current_scene.get_children():
		if c is EnemyProjectile:
			spawned_proj = c as EnemyProjectile
			break
	if spawned_proj == null:
		printerr("TEST FAILED: shooter did not spawn EnemyProjectile.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	if spawned_proj.get_parent() != get_tree().current_scene or spawned_proj.shooter != shooter:
		printerr("TEST FAILED: Projectile not parented to world container with shooter reference.")
		shooter.queue_free()
		test_player.queue_free()
		spawned_proj.queue_free()
		get_tree().quit(1)
		return
	print("Projectile parented to world container with shooter reference verified.")
	if not is_equal_approx(spawned_proj.global_rotation.y, shooter.mesh_mount.global_rotation.y):
		printerr("TEST FAILED: Spawned projectile rotation.y does not match mesh_mount.global_rotation.y.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("Spawned projectile rotation.y matches mesh_mount.global_rotation.y verified.")

	# Verify position matched spawn_point
	if not spawned_proj.global_position.is_equal_approx(spawner_comp.spawn_point.global_position):
		printerr("TEST FAILED: Spawned projectile position does not match spawn_point.")
		shooter.queue_free()
		test_player.queue_free()
		spawned_proj.queue_free()
		get_tree().quit(1)
		return
	print("Spawned projectile position matches attack_bone.")
	spawned_proj.queue_free()

	# Test projectile collision & damage dealing
	var target_health: HealthComponent = test_player.get_node_or_null("HealthComponent") as HealthComponent
	var initial_health: float = target_health.current_health
	# Place projectile directly at test_player to trigger Area3D collision
	var child_count_before: int = get_child_count()
	var hit_proj: EnemyProjectile = proj_scene.instantiate() as EnemyProjectile
	add_child(hit_proj)
	hit_proj.global_position = test_player.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var spawned_hit: Node3D = null
	for i: int in range(child_count_before, get_child_count()):
		var c: Node = get_child(i)
		if c.name.begins_with("FireballHit"):
			spawned_hit = c as Node3D
			break
	if spawned_hit == null:
		printerr("TEST FAILED: hit_effect() did not spawn FireballHit into world container.")
		shooter.queue_free()
		test_player.queue_free()
		hit_proj.queue_free()
		get_tree().quit(1)
		return
	if not spawned_hit.global_position.is_equal_approx(hit_proj.global_position):
		printerr("TEST FAILED: Spawned FireballHit position does not match projectile position.")
		shooter.queue_free()
		test_player.queue_free()
		hit_proj.queue_free()
		spawned_hit.queue_free()
		get_tree().quit(1)
		return
	spawned_hit.queue_free()
	print("Projectile hit_effect() spawned FireballHit at projectile position verified.")

	if not is_equal_approx(target_health.current_health, initial_health - hit_proj.damage):
		printerr("TEST FAILED: Target health was not reduced by projectile damage. Expected ", initial_health - hit_proj.damage, ", got ", target_health.current_health)
		shooter.queue_free()
		test_player.queue_free()
		hit_proj.queue_free()
		get_tree().quit(1)
		return
	print("Projectile dealt damage via AttackComponent verified! Health: ", target_health.current_health)

	if not hit_proj.is_queued_for_deletion():
		printerr("TEST FAILED: Projectile was not queued for deletion on collision.")
		shooter.queue_free()
		test_player.queue_free()
		hit_proj.queue_free()
		get_tree().quit(1)
		return
	print("Projectile deleted on collision (body_entered -> queue_free()) verified.")

	shooter.queue_free()
	test_player.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 10: Navigation Map Random Point & Enemy Positioning
	# ---------------------------------------------------------
	print("\n>>> PART 10: Navigation Map Random Point & Enemy Positioning")
	var nav_level: Node3D = level_scene.instantiate() as Node3D
	add_child(nav_level)
	await get_tree().physics_frame
	await get_tree().process_frame

	var map_rid: RID = nav_level.get_world_3d().navigation_map
	var random_point: Vector3 = NavigationServer3D.map_get_random_point(map_rid, 1, true)
	if not random_point.is_finite():
		printerr("TEST FAILED: NavigationServer3D map_get_random_point returned non-finite point: ", random_point)
		nav_level.queue_free()
		get_tree().quit(1)
		return
	print("NavigationServer3D map_get_random_point returned valid point: ", random_point)

	nav_level.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

	print("\n>>> PART 11: UpgradeShop Scene & UI Verification")
	# Verify GlobalVars registry exports and array
	if GlobalVars.upgrade_icon_scene == null or GlobalVars.upgrade_damage == null or GlobalVars.upgrade_health == null or GlobalVars.upgrade_speed == null or GlobalVars.upgrade_potion == null:
		printerr("TEST FAILED: GlobalVars upgrade exports missing or null.")
		get_tree().quit(1)
		return
	if not (GlobalVars.upgrade_damage is UpgradeResource) or not (GlobalVars.upgrade_health is UpgradeResource) or not (GlobalVars.upgrade_speed is UpgradeResource) or not (GlobalVars.upgrade_potion is UpgradeResource):
		printerr("TEST FAILED: GlobalVars upgrades are not UpgradeResource instances.")
		get_tree().quit(1)
		return
	if GlobalVars.upgrades.size() != 4:
		printerr("TEST FAILED: GlobalVars.upgrades does not contain 4 upgrades. Size: ", GlobalVars.upgrades.size())
		get_tree().quit(1)
		return
	if not GlobalVars.upgrades.has(GlobalVars.upgrade_damage) or not GlobalVars.upgrades.has(GlobalVars.upgrade_health) or not GlobalVars.upgrades.has(GlobalVars.upgrade_speed) or not GlobalVars.upgrades.has(GlobalVars.upgrade_potion):
		printerr("TEST FAILED: GlobalVars.upgrades array missing required upgrade resources.")
		get_tree().quit(1)
		return
	if GlobalVars.difficulty_curve == null or GlobalVars.enemy_melee_scene == null or GlobalVars.enemy_ranged_scene == null or GlobalVars.enemy_projectile_scene == null or GlobalVars.fireball_hit_scene == null or GlobalVars.damage_number_scene == null or GlobalVars.upgrade_shop_scene == null:
		printerr("TEST FAILED: GlobalVars registry exports missing or null.")
		get_tree().quit(1)
		return
	print("GlobalVars registry exports and upgrades array verified.")

	var shop_scene: PackedScene = load("res://UserInterface/upgrade_shop.tscn") as PackedScene
	if shop_scene == null:
		printerr("TEST FAILED: Failed to load res://UserInterface/upgrade_shop.tscn")
		get_tree().quit(1)
		return

	var shop: Control = shop_scene.instantiate() as Control
	if shop == null:
		printerr("TEST FAILED: UpgradeShop root is not a Control node.")
		get_tree().quit(1)
		return

	var shop_script: Script = shop.get_script() as Script
	if shop_script == null or shop_script.resource_path != "res://UserInterface/upgrade_shop.gd":
		printerr("TEST FAILED: UpgradeShop script is not res://UserInterface/upgrade_shop.gd")
		shop.queue_free()
		get_tree().quit(1)
		return

	var color_rect: ColorRect = shop.get_node_or_null("ColorRect") as ColorRect
	if color_rect == null or color_rect.material == null or not (color_rect.material is ShaderMaterial):
		printerr("TEST FAILED: UpgradeShop ColorRect or ShaderMaterial missing.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var shader_mat: ShaderMaterial = color_rect.material as ShaderMaterial
	if shader_mat.shader == null or shader_mat.get_shader_parameter("NoiseTexture") == null or shader_mat.get_shader_parameter("GradientTexture") == null:
		printerr("TEST FAILED: UpgradeShop ShaderMaterial shader or parameters missing.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var margin_container: MarginContainer = shop.get_node_or_null("MarginContainer") as MarginContainer
	if margin_container == null:
		printerr("TEST FAILED: UpgradeShop MarginContainer missing.")
		shop.queue_free()
		get_tree().quit(1)
		return

	if margin_container.get_theme_constant("margin_left") != 128 or margin_container.get_theme_constant("margin_top") != 128 \
		or margin_container.get_theme_constant("margin_right") != 128 or margin_container.get_theme_constant("margin_bottom") != 128:
		printerr("TEST FAILED: UpgradeShop MarginContainer margins are not 128.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var vbox: VBoxContainer = margin_container.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		printerr("TEST FAILED: UpgradeShop VBoxContainer missing.")
		shop.queue_free()
		get_tree().quit(1)
	var title_label: RichTextLabel = vbox.get_node_or_null("RichTextLabel") as RichTextLabel
	if title_label == null or not title_label.bbcode_enabled or not title_label.fit_content or title_label.text != "[center][wave]Upgrade Shop[/wave][/center]":
		printerr("TEST FAILED: UpgradeShop RichTextLabel title missing or configured improperly.")
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop scene hierarchy, shader material, margin container, and title label verified.")

	var hbox: HBoxContainer = vbox.get_node_or_null("HBoxContainer") as HBoxContainer
	if hbox == null or hbox.size_flags_vertical != 6:
		printerr("TEST FAILED: UpgradeShop HBoxContainer missing or size_flags_vertical != 6")
		shop.queue_free()
		get_tree().quit(1)
		return

	# Add shop to tree so _ready() populates upgrades dynamically
	add_child(shop)
	await get_tree().process_frame

	# Verify upgrade_container onready reference
	if shop.upgrade_container != hbox:
		printerr("TEST FAILED: UpgradeShop upgrade_container does not match HBoxContainer.")
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop upgrade_container onready reference verified.")

	# Verify 2 dynamic upgrades were instantiated into upgrade_container
	if shop.upgrade_container.get_child_count() != 2:
		printerr("TEST FAILED: Expected 2 dynamic upgrades in upgrade_container, got: ", shop.upgrade_container.get_child_count())
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop dynamically generated 2 upgrade options successfully.")

	# Verify each child is an UpgradeIcon with size_flags_horizontal == 6, upgrade_resource set, and upgrade_taken connected to shop.exit_shop
	for child: Node in shop.upgrade_container.get_children():
		var icon: UpgradeIcon = child as UpgradeIcon
		if icon == null:
			printerr("TEST FAILED: Child of upgrade_container is not an UpgradeIcon.")
			shop.queue_free()
			get_tree().quit(1)
			return
		if icon.upgrade_resource == null:
			printerr("TEST FAILED: UpgradeIcon child upgrade_resource is null.")
			shop.queue_free()
			get_tree().quit(1)
			return
		if icon.size_flags_horizontal != 6:
			printerr("TEST FAILED: UpgradeIcon size_flags_horizontal is not 6 (shrink center & expand). Got: ", icon.size_flags_horizontal)
			shop.queue_free()
			get_tree().quit(1)
			return
		if not icon.upgrade_taken.is_connected(shop.exit_shop):
			printerr("TEST FAILED: UpgradeIcon ", icon.name, " upgrade_taken signal is not connected to exit_shop.")
			shop.queue_free()
			get_tree().quit(1)
			return
	print("UpgradeShop dynamic upgrade children verified (UpgradeIcon type, upgrade_resource set, size_flags_horizontal 6, upgrade_taken connected).")

	# Verify exiting_shop guard
	if shop.exiting_shop:
		printerr("TEST FAILED: UpgradeShop exiting_shop should initially be false.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var first_icon: UpgradeIcon = shop.upgrade_container.get_child(0) as UpgradeIcon
	shop.exit_shop(first_icon)
	if not shop.exiting_shop:
		printerr("TEST FAILED: UpgradeShop exiting_shop was not set to true after exit_shop.")
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop exit_shop execution and exiting_shop flag verified.")

	shop.queue_free()
	await get_tree().process_frame

	print("\n>>> PART 12: Window Stretch & Fullscreen Action Verification")
	if not InputMap.has_action("ui_toggle_fullscreen"):
		printerr("TEST FAILED: ui_toggle_fullscreen not found in InputMap")
		get_tree().quit(1)
		return
	var fs_events: Array[InputEvent] = InputMap.action_get_events("ui_toggle_fullscreen")
	if fs_events.is_empty():
		printerr("TEST FAILED: ui_toggle_fullscreen has no events bound")
		get_tree().quit(1)
		return
	var key_event: InputEventKey = fs_events[0] as InputEventKey
	if key_event == null or (key_event.physical_keycode == 0 and key_event.keycode == 0):
		printerr("TEST FAILED: ui_toggle_fullscreen has no valid key event bound.")
		get_tree().quit(1)
		return
	print("InputMap ui_toggle_fullscreen key event verified.")

	if not UI.has_method("toggle_fullscreen") or not UI.has_method("is_fullscreen") or not UI.has_method("go_fullscreen"):
		printerr("TEST FAILED: UI missing toggle_fullscreen / is_fullscreen / go_fullscreen methods")
		get_tree().quit(1)
		return
	UI.toggle_fullscreen()
	print("UI.toggle_fullscreen() executed successfully.")

	var fs_action_event := InputEventAction.new()
	fs_action_event.action = "ui_toggle_fullscreen"
	fs_action_event.pressed = true
	UI._unhandled_key_input(fs_action_event)
	print("UI._unhandled_key_input with ui_toggle_fullscreen verified.")

	var stretch_mode: Variant = ProjectSettings.get_setting("display/window/stretch/mode")
	var stretch_aspect: Variant = ProjectSettings.get_setting("display/window/stretch/aspect")
	if stretch_mode != "canvas_items" or stretch_aspect != "expand":
		printerr("TEST FAILED: Window stretch settings incorrect: mode=", stretch_mode, " aspect=", stretch_aspect)
		get_tree().quit(1)
		return
	print("Window stretch settings (mode=canvas_items, aspect=expand) verified.")

	print("\n>>> PART 13: Base Upgrade Icon Verification")
	var upgrade_icon_scene: PackedScene = load("res://UserInterface/upgrade_icon.tscn")
	if upgrade_icon_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_icon.tscn")
		get_tree().quit(1)
		return

	var icon_inst: UpgradeIcon = upgrade_icon_scene.instantiate() as UpgradeIcon
	if icon_inst == null:
		printerr("TEST FAILED: upgrade_icon is not an instance of class_name UpgradeIcon")
		get_tree().quit(1)
		return
	if not (icon_inst is PanelContainer):
		printerr("TEST FAILED: UpgradeIcon is not a PanelContainer")
		get_tree().quit(1)
		return

	if icon_inst.custom_minimum_size != Vector2(256, 160):
		printerr("TEST FAILED: UpgradeIcon custom_minimum_size is not Vector2(256, 160), got: ", icon_inst.custom_minimum_size)
		get_tree().quit(1)
		return

	if icon_inst.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: UpgradeIcon mouse_filter is not MOUSE_FILTER_IGNORE")
		get_tree().quit(1)
		return

	var panel_style: StyleBoxFlat = icon_inst.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style == null:
		printerr("TEST FAILED: UpgradeIcon does not have a StyleBoxFlat panel style")
		get_tree().quit(1)
		return
	if panel_style.border_width_top != 4 or panel_style.border_width_left != 1 or panel_style.border_width_right != 1 or panel_style.border_width_bottom != 1:
		printerr("TEST FAILED: UpgradeIcon StyleBoxFlat border widths incorrect")
		get_tree().quit(1)
		return

	add_child(icon_inst)
	await get_tree().process_frame

	var vbox_node: VBoxContainer = icon_inst.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox_node == null or vbox_node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: UpgradeIcon VBoxContainer mouse_filter is not MOUSE_FILTER_IGNORE")
		get_tree().quit(1)
		return

	var control_node: Control = vbox_node.get_node_or_null("Control") as Control
	if control_node == null or control_node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: UpgradeIcon Control mouse_filter is not MOUSE_FILTER_IGNORE")
		get_tree().quit(1)
		return

	if icon_inst.texture_button == null:
		printerr("TEST FAILED: UpgradeIcon texture_button is null")
		get_tree().quit(1)
		return
	if icon_inst.title == null or icon_inst.title.text != "[wave]Upgrade[/wave]" or icon_inst.title.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: UpgradeIcon title is null or misconfigured")
		get_tree().quit(1)
		return
	if icon_inst.description == null or icon_inst.description.text != "A description of the upgrade." or icon_inst.description.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: UpgradeIcon description is null or misconfigured")
		get_tree().quit(1)
		return
	if icon_inst.text_template != "%.1f -> [color='7fffd4']%.1f[/color] m/s":
		printerr("TEST FAILED: UpgradeIcon text_template incorrect: ", icon_inst.text_template)
		get_tree().quit(1)
		return
	if icon_inst.stat_name != "" or icon_inst.stat_bonus != 0.0:
		printerr("TEST FAILED: UpgradeIcon default stat_name or stat_bonus incorrect")
		get_tree().quit(1)
		return

	icon_inst.queue_free()
	print("Base UpgradeIcon scene, theme, nodes, and exports verified.")

	# Test UpgradeSpeed resource and dynamic card filling
	var speed_res: UpgradeResource = load("res://UserInterface/UpgradeResources/upgrade_speed.tres") as UpgradeResource
	if speed_res == null:
		printerr("TEST FAILED: Could not load res://UserInterface/UpgradeResources/upgrade_speed.tres")
		get_tree().quit(1)
		return
	if speed_res.stat_name != "movement_speed" or speed_res.stat_bonus != 1.5:
		printerr("TEST FAILED: UpgradeSpeed stat_name or stat_bonus incorrect. Got: ", speed_res.stat_name, ", ", speed_res.stat_bonus)
		get_tree().quit(1)
		return
	if speed_res.text_template != "%.1f -> [color=\"7fffd4\"]%.1f[/color] m/s":
		printerr("TEST FAILED: UpgradeSpeed text_template incorrect: ", speed_res.text_template)
		get_tree().quit(1)
		return
	if speed_res.title != "[wave]Speed[/wave]":
		printerr("TEST FAILED: UpgradeSpeed title incorrect: ", speed_res.title)
		get_tree().quit(1)
		return

	var speed_icon: UpgradeIcon = upgrade_icon_scene.instantiate() as UpgradeIcon
	speed_icon.set_upgrade_resource(speed_res)
	var player_scene_upgrade: PackedScene = load("res://Player/player.tscn")
	var upgrade_player: Character = player_scene_upgrade.instantiate() as Character
	add_child(upgrade_player)
	add_child(speed_icon)
	await get_tree().process_frame

	if speed_icon.title.text != "[wave]Speed[/wave]":
		printerr("TEST FAILED: UpgradeSpeed Title text is not [wave]Speed[/wave], got: ", speed_icon.title.text)
		get_tree().quit(1)
		return

	if not speed_icon.description.bbcode_enabled:
		printerr("TEST FAILED: UpgradeSpeed description bbcode_enabled is false")
		get_tree().quit(1)
		return

	var expected_desc: String = "8.0 -> [color=\"7fffd4\"]9.5[/color] m/s"
	if speed_icon.description.text != expected_desc:
		printerr("TEST FAILED: UpgradeSpeed description.text did not match formatted template. Got: '", speed_icon.description.text, "', expected: '", expected_desc, "'")
		get_tree().quit(1)
		return
	print("UpgradeSpeed setup_label() text formatting verified: ", speed_icon.description.text)

	var base_speed: float = upgrade_player.movement_speed
	var speed_taken_emitted: Array[UpgradeIcon] = []
	speed_icon.upgrade_taken.connect(func(taken_icon: UpgradeIcon) -> void: speed_taken_emitted.append(taken_icon))
	speed_icon.take_upgrade()
	if speed_taken_emitted.is_empty() or speed_taken_emitted[0] != speed_icon:
		printerr("TEST FAILED: speed_icon did not emit upgrade_taken with self as argument")
		get_tree().quit(1)
		return
	print("UpgradeIcon upgrade_taken signal emitted with self verified.")
	if not is_equal_approx(upgrade_player.movement_speed, base_speed + 1.5):
		printerr("TEST FAILED: take_upgrade did not increase player movement_speed by 1.5. Got: ", upgrade_player.movement_speed)
		get_tree().quit(1)
		return
	print("take_upgrade() successfully modified player movement_speed from ", base_speed, " to ", upgrade_player.movement_speed)

	# Verify texture_button is disabled after taking upgrade
	if not speed_icon.texture_button.disabled:
		printerr("TEST FAILED: speed_icon texture_button was not disabled after take_upgrade.")
		get_tree().quit(1)
		return
	print("UpgradeIcon texture_button is disabled after take_upgrade verified.")

	# Verify clicking or calling take_upgrade again does NOT increase speed
	speed_icon.texture_button.pressed.emit()
	speed_icon.take_upgrade()
	if not is_equal_approx(upgrade_player.movement_speed, base_speed + 1.5):
		printerr("TEST FAILED: take_upgrade applied bonus again while disabled! Speed: ", upgrade_player.movement_speed)
		get_tree().quit(1)
		return
	print("UpgradeIcon multiple click prevention verified (speed remained ", upgrade_player.movement_speed, ").")

	speed_icon.queue_free()
	upgrade_player.queue_free()
	await get_tree().process_frame

	# Test UpgradeDamage resource and dynamic card filling
	var damage_res: UpgradeResource = load("res://UserInterface/UpgradeResources/upgrade_damage.tres") as UpgradeResource
	if damage_res == null:
		printerr("TEST FAILED: Could not load res://UserInterface/UpgradeResources/upgrade_damage.tres")
		get_tree().quit(1)
		return
	if damage_res.stat_name != "damage_stat" or damage_res.stat_bonus != 50.0:
		printerr("TEST FAILED: UpgradeDamage stat_name or stat_bonus incorrect. Got: ", damage_res.stat_name, ", ", damage_res.stat_bonus)
		get_tree().quit(1)
		return
	if damage_res.text_template != "%d%% -> [color='7fffd4']%d%%[/color] damage":
		printerr("TEST FAILED: UpgradeDamage text_template incorrect: ", damage_res.text_template)
		get_tree().quit(1)
		return
	if damage_res.title != "[wave]Damage[/wave]":
		printerr("TEST FAILED: UpgradeDamage title incorrect: ", damage_res.title)
		get_tree().quit(1)
		return

	var damage_icon: UpgradeIcon = upgrade_icon_scene.instantiate() as UpgradeIcon
	damage_icon.set_upgrade_resource(damage_res)
	var player_scene_dmg: PackedScene = load("res://Player/player.tscn")
	var dmg_player: Character = player_scene_dmg.instantiate() as Character
	add_child(dmg_player)
	add_child(damage_icon)
	await get_tree().process_frame

	if damage_icon.title.text != "[wave]Damage[/wave]":
		printerr("TEST FAILED: UpgradeDamage Title text is not [wave]Damage[/wave], got: ", damage_icon.title.text)
		get_tree().quit(1)
		return

	if not damage_icon.description.bbcode_enabled:
		printerr("TEST FAILED: UpgradeDamage description bbcode_enabled is false")
		get_tree().quit(1)
		return

	var expected_dmg_desc: String = "100% -> [color='7fffd4']150%[/color] damage"
	if damage_icon.description.text != expected_dmg_desc:
		printerr("TEST FAILED: UpgradeDamage description.text did not match formatted template. Got: '", damage_icon.description.text, "', expected: '", expected_dmg_desc, "'")
		get_tree().quit(1)
		return
	print("UpgradeDamage setup_label() text formatting verified: ", damage_icon.description.text)

	if dmg_player.damage_stat != 100.0 or not is_equal_approx(dmg_player.get_damage_modifier(), 1.0):
		printerr("TEST FAILED: Initial damage_stat or get_damage_modifier incorrect")
		get_tree().quit(1)
		return

	damage_icon.take_upgrade()
	if dmg_player.damage_stat != 150.0 or not is_equal_approx(dmg_player.get_damage_modifier(), 1.5):
		printerr("TEST FAILED: take_upgrade did not increase damage_stat to 150.0 / modifier to 1.5")
		get_tree().quit(1)
		return
	print("take_upgrade() successfully modified damage_stat to 150.0 and get_damage_modifier() to 1.5")

	if not damage_icon.texture_button.disabled:
		printerr("TEST FAILED: damage_icon texture_button was not disabled after take_upgrade.")
		get_tree().quit(1)
		return

	damage_icon.queue_free()
	dmg_player.queue_free()
	await get_tree().process_frame

	# Test UpgradeHealth resource and dynamic card filling
	var health_res: UpgradeResource = load("res://UserInterface/UpgradeResources/upgrade_health.tres") as UpgradeResource
	if health_res == null:
		printerr("TEST FAILED: Could not load res://UserInterface/UpgradeResources/upgrade_health.tres")
		get_tree().quit(1)
		return
	if health_res.upgrade_type != UpgradeResource.UpgradeType.MAX_HEALTH or health_res.stat_bonus != 20.0:
		printerr("TEST FAILED: UpgradeHealth default upgrade_type or stat_bonus incorrect. Got: ", health_res.upgrade_type, ", ", health_res.stat_bonus)
		get_tree().quit(1)
		return
	if health_res.text_template != "%d -> [color='7fffd4']%d[/color] HP":
		printerr("TEST FAILED: UpgradeHealth text_template incorrect: ", health_res.text_template)
		get_tree().quit(1)
		return
	if health_res.title != "[wave]Max Health[/wave]":
		printerr("TEST FAILED: UpgradeHealth title incorrect: ", health_res.title)
		get_tree().quit(1)
		return

	var health_icon: UpgradeIcon = upgrade_icon_scene.instantiate() as UpgradeIcon
	health_icon.set_upgrade_resource(health_res)
	var player_scene_hp: PackedScene = load("res://Player/player.tscn")
	var hp_player: Character = player_scene_hp.instantiate() as Character
	add_child(hp_player)
	hp_player.health_component.take_damage(20.0) # Reduce health from 60 to 40
	add_child(health_icon)
	await get_tree().process_frame

	if health_icon.title.text != "[wave]Max Health[/wave]":
		printerr("TEST FAILED: UpgradeHealth Title text is not [wave]Max Health[/wave], got: ", health_icon.title.text)
		get_tree().quit(1)
		return

	var expected_hp_desc: String = "60 -> [color='7fffd4']80[/color] HP"
	if health_icon.description.text != expected_hp_desc:
		printerr("TEST FAILED: UpgradeHealth description.text did not match formatted template. Got: '", health_icon.description.text, "', expected: '", expected_hp_desc, "'")
		get_tree().quit(1)
		return
	print("UpgradeHealth setup_label() text formatting verified: ", health_icon.description.text)

	var initial_max_health: float = hp_player.health_component.max_health
	var initial_current_health: float = hp_player.health_component.current_health
	var health_taken_emitted: Array[UpgradeIcon] = []
	health_icon.upgrade_taken.connect(func(taken_icon: UpgradeIcon) -> void: health_taken_emitted.append(taken_icon))
	health_icon.take_upgrade()
	if health_taken_emitted.is_empty() or health_taken_emitted[0] != health_icon:
		printerr("TEST FAILED: health_icon did not emit upgrade_taken with self via take_upgrade()")
		get_tree().quit(1)
		return
	print("UpgradeHealth upgrade_taken signal emission verified.")
	if not is_equal_approx(hp_player.health_component.max_health, initial_max_health + 20.0):
		printerr("TEST FAILED: take_upgrade did not increase max_health by 20. Got: ", hp_player.health_component.max_health)
		get_tree().quit(1)
		return
	if not is_equal_approx(hp_player.health_component.current_health, initial_current_health + 20.0):
		printerr("TEST FAILED: take_upgrade did not increase current_health by 20. Got: ", hp_player.health_component.current_health)
		get_tree().quit(1)
		return
	print("take_upgrade() successfully increased max_health to ", hp_player.health_component.max_health, " and current_health to ", hp_player.health_component.current_health)

	# Verify player HealthBar updated immediately
	var player_health_bar: HealthBar = hp_player.get_node_or_null("HealthBar") as HealthBar
	if player_health_bar == null:
		printerr("TEST FAILED: HealthBar node not found on hp_player")
		get_tree().quit(1)
		return
	var expected_hp_pct: float = (hp_player.health_component.current_health / hp_player.health_component.max_health) * 100.0
	if not is_equal_approx(player_health_bar.front_progress_bar.value, expected_hp_pct):
		printerr("TEST FAILED: HealthBar front_progress_bar.value did not update immediately upon health upgrade! Expected ", expected_hp_pct, ", got: ", player_health_bar.front_progress_bar.value)
		get_tree().quit(1)
		return
	if not is_equal_approx(player_health_bar.health_progress_bar.value, expected_hp_pct):
		printerr("TEST FAILED: HealthBar health_progress_bar.value did not update immediately upon health upgrade! Expected ", expected_hp_pct, ", got: ", player_health_bar.health_progress_bar.value)
		get_tree().quit(1)
		return
	print("HealthBar front and background bars immediately updated to ", expected_hp_pct, "% successfully!")

	if not health_icon.texture_button.disabled:
		printerr("TEST FAILED: health_icon texture_button was not disabled after take_upgrade.")
		get_tree().quit(1)
		return

	# Verify multi-click guard prevents repeated health increases
	health_icon.take_upgrade()
	health_icon.texture_button.pressed.emit()
	if not is_equal_approx(hp_player.health_component.max_health, initial_max_health + 20.0):
		printerr("TEST FAILED: health_icon applied bonus again while disabled! max_health: ", hp_player.health_component.max_health)
		get_tree().quit(1)
		return
	print("UpgradeHealth multiple click prevention verified.")

	health_icon.queue_free()
	hp_player.queue_free()
	await get_tree().process_frame

	# Test UpgradePotion resource and dynamic card filling
	var potion_res: UpgradeResource = load("res://UserInterface/UpgradeResources/upgrade_potion.tres") as UpgradeResource
	if potion_res == null:
		printerr("TEST FAILED: Could not load res://UserInterface/UpgradeResources/upgrade_potion.tres")
		get_tree().quit(1)
		return
	if potion_res.upgrade_type != UpgradeResource.UpgradeType.HEAL_PERCENT or potion_res.stat_bonus != 50.0:
		printerr("TEST FAILED: UpgradePotion default upgrade_type or stat_bonus incorrect. Got: ", potion_res.upgrade_type, ", ", potion_res.stat_bonus)
		get_tree().quit(1)
		return
	if potion_res.title != "[wave]Potion[/wave]":
		printerr("TEST FAILED: UpgradePotion title incorrect: ", potion_res.title)
		get_tree().quit(1)
		return

	var potion_icon: UpgradeIcon = upgrade_icon_scene.instantiate() as UpgradeIcon
	potion_icon.set_upgrade_resource(potion_res)
	var player_scene_potion: PackedScene = load("res://Player/player.tscn")
	var potion_player: Character = player_scene_potion.instantiate() as Character
	add_child(potion_player)
	potion_player.health_component.take_damage(40.0) # Reduce health from 60 to 20 (max_health = 60)
	add_child(potion_icon)
	await get_tree().process_frame

	if potion_icon.title.text != "[wave]Potion[/wave]":
		printerr("TEST FAILED: UpgradePotion Title text is not [wave]Potion[/wave], got: ", potion_icon.title.text)
		get_tree().quit(1)
		return

	var expected_potion_desc: String = "20 -> [color='7fffd4']50[/color] HP"
	if potion_icon.description.text != expected_potion_desc:
		printerr("TEST FAILED: UpgradePotion description.text did not match formatted template. Got: '", potion_icon.description.text, "', expected: '", expected_potion_desc, "'")
		get_tree().quit(1)
		return
	print("UpgradePotion setup_label() text formatting verified: ", potion_icon.description.text)

	var potion_taken_emitted: Array[UpgradeIcon] = []
	potion_icon.upgrade_taken.connect(func(taken_icon: UpgradeIcon) -> void: potion_taken_emitted.append(taken_icon))
	potion_icon.take_upgrade()
	if potion_taken_emitted.is_empty() or potion_taken_emitted[0] != potion_icon:
		printerr("TEST FAILED: potion_icon did not emit upgrade_taken with self via take_upgrade()")
		get_tree().quit(1)
		return
	print("UpgradePotion upgrade_taken signal emission verified.")
	if not is_equal_approx(potion_player.health_component.max_health, 60.0):
		printerr("TEST FAILED: take_upgrade should not change max_health. Got: ", potion_player.health_component.max_health)
		get_tree().quit(1)
		return
	if not is_equal_approx(potion_player.health_component.current_health, 50.0):
		printerr("TEST FAILED: take_upgrade did not heal 50% max_health (+30) from 20 to 50. Got: ", potion_player.health_component.current_health)
		get_tree().quit(1)
		return
	print("take_upgrade() successfully healed player from 20.0 to ", potion_player.health_component.current_health, " (50% of max health 60.0)")

	# Verify player HealthBar updated immediately
	var potion_health_bar: HealthBar = potion_player.get_node_or_null("HealthBar") as HealthBar
	if potion_health_bar == null:
		printerr("TEST FAILED: HealthBar node not found on potion_player")
		get_tree().quit(1)
		return
	var expected_potion_hp_pct: float = (50.0 / 60.0) * 100.0
	if abs(potion_health_bar.front_progress_bar.value - expected_potion_hp_pct) > 0.1:
		printerr("TEST FAILED: HealthBar front_progress_bar.value did not update immediately upon potion heal! Got: ", potion_health_bar.front_progress_bar.value, ", expected: ", expected_potion_hp_pct)
		get_tree().quit(1)
		return

	if not potion_icon.texture_button.disabled:
		printerr("TEST FAILED: potion_icon texture_button was not disabled after take_upgrade.")
		get_tree().quit(1)
		return

	# Verify multi-click guard prevents repeated heals
	potion_icon.take_upgrade()
	potion_icon.texture_button.pressed.emit()
	if not is_equal_approx(potion_player.health_component.current_health, 50.0):
		printerr("TEST FAILED: potion_icon applied heal again while disabled! current_health: ", potion_player.health_component.current_health)
		get_tree().quit(1)
		return
	print("UpgradePotion multiple click prevention verified.")

	# Verify cap at max_health
	potion_res.apply(potion_player) # Heals +30 from 50 -> should cap at 60
	if not is_equal_approx(potion_player.health_component.current_health, 60.0):
		printerr("TEST FAILED: Potion heal did not cap at max_health! current_health: ", potion_player.health_component.current_health)
		get_tree().quit(1)
		return
	print("UpgradePotion max_health cap verified (healed 50 -> 60, capped at max 60).")

	potion_icon.queue_free()
	potion_player.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 28: MeleeEnemy & EnemyPursue Verification (Lecture 81)
	# ---------------------------------------------------------
	print("\n>>> PART 28: MeleeEnemy & EnemyPursue Verification")
	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	if melee_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/melee_enemy.tscn")
		get_tree().quit(1)
		return
	var melee_enemy: Character = melee_scene.instantiate() as Character
	if melee_enemy == null or not (melee_enemy is Character) or not melee_enemy.is_in_group("enemy"):
		printerr("TEST FAILED: MeleeEnemy root node is not a Character instance in group 'enemy'.")
		get_tree().quit(1)
		return
	var melee_floor := StaticBody3D.new()
	var mf_col := CollisionShape3D.new()
	var mf_box := BoxShape3D.new()
	mf_box.size = Vector3(20.0, 1.0, 20.0)
	mf_col.shape = mf_box
	mf_col.position = Vector3(0.0, -0.5, 0.0)
	melee_floor.add_child(mf_col)
	add_child(melee_floor)

	melee_enemy.position = Vector3(0.0, 1.0, 0.0)
	add_child(melee_enemy)
	melee_enemy.velocity = Vector3(0.0, -1.0, 0.0)
	melee_enemy.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame

	var melee_sm: StateMachine = melee_enemy.get_node_or_null("StateMachine") as StateMachine
	if melee_sm == null:
		printerr("TEST FAILED: StateMachine not found in MeleeEnemy.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	var move_node: EnemyMove = melee_sm.get_node_or_null("EnemyMove") as EnemyMove
	if move_node == null:
		printerr("TEST FAILED: EnemyMove node not found under MeleeEnemy StateMachine.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	if melee_sm.initial_state != move_node:
		printerr("TEST FAILED: MeleeEnemy initial_state is not EnemyMove. Got: ", melee_sm.initial_state)
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy body initial_state is EnemyMove.")

	var melee_ai_sm: AIStateMachine = melee_enemy.ai_state_machine as AIStateMachine
	if melee_ai_sm == null:
		printerr("TEST FAILED: AIStateMachine not found in MeleeEnemy.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	var pursue_node: AIPursue = melee_ai_sm.get_node_or_null("AIPursue") as AIPursue
	if pursue_node == null:
		printerr("TEST FAILED: AIPursue node not found under MeleeEnemy AIStateMachine.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	if melee_ai_sm.initial_state != pursue_node:
		printerr("TEST FAILED: MeleeEnemy AI initial_state is not AIPursue. Got: ", melee_ai_sm.initial_state)
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy AI initial_state is AIPursue.")

	if pursue_node.attack_state_name != "EnemyAttack":
		printerr("TEST FAILED: AIPursue.attack_state_name is not EnemyAttack.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("AIPursue.attack_state_name export verified.")

	if pursue_node.character != melee_enemy:
		printerr("TEST FAILED: AIPursue.character does not point to MeleeEnemy.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("AIPursue.character reference verified.")

	var melee_wait_node: AIWait = melee_ai_sm.get_node_or_null("AIWait") as AIWait
	if melee_wait_node == null:
		printerr("TEST FAILED: AIWait node not found under MeleeEnemy AIStateMachine.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	if melee_wait_node.next_state != pursue_node:
		printerr("TEST FAILED: MeleeEnemy AIWait next_state is not AIPursue.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	if pursue_node.lost_target_state != melee_wait_node:
		printerr("TEST FAILED: MeleeEnemy AIPursue lost_target_state is not AIWait.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy AIWait <-> AIPursue loop verified.")

	# Verify move_node fall_state export points to EnemyFall
	var melee_fall: EnemyFall = melee_sm.get_node_or_null("EnemyFall") as EnemyFall
	if melee_fall == null or move_node.fall_state != melee_fall:
		printerr("TEST FAILED: EnemyMove.fall_state is not wired to EnemyFall.")
		melee_enemy.queue_free()
		melee_floor.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy hierarchy, StateMachine, AIStateMachine, and EnemyFall wiring verified.")

	melee_floor.queue_free()
	melee_enemy.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 29: Melee Attack, AnimationTree & Pursue Transition (Lecture 82)
	# ---------------------------------------------------------
	print("\n>>> PART 29: Melee Attack, AnimationTree & Pursue Transition")
	# 1. Verify Melee_2H_Attack_Chop animation resource exists
	var chop_anim: Animation = load("res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_2H_Attack_Chop.res") as Animation
	if chop_anim == null or chop_anim.length <= 0.0:
		printerr("TEST FAILED: Melee_2H_Attack_Chop.res missing or invalid.")
		get_tree().quit(1)
		return
	print("Melee_2H_Attack_Chop animation resource verified (length: ", chop_anim.length, ").")

	# 2. Verify AnimatedEnemy scene AnimationPlayer and AnimationTree
	var anim_enemy_scene: PackedScene = load("res://Enemy/animated_enemy.tscn")
	if anim_enemy_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/animated_enemy.tscn")
		get_tree().quit(1)
		return
	var anim_enemy: Node3D = anim_enemy_scene.instantiate() as Node3D
	add_child(anim_enemy)
	var chop_anim_player: AnimationPlayer = anim_enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if chop_anim_player == null:
		printerr("TEST FAILED: AnimationPlayer not found in AnimatedEnemy.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	if not chop_anim_player.has_animation_library(&"EnemyAnimations") or not chop_anim_player.get_animation_library(&"EnemyAnimations").has_animation(&"Melee_2H_Attack_Chop"):
		printerr("TEST FAILED: AnimationPlayer missing Melee_2H_Attack_Chop in EnemyAnimations library.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	var chop_anim_tree: AnimationTree = anim_enemy.find_child("AnimationTree", true, false) as AnimationTree
	if chop_anim_tree == null or not (chop_anim_tree.tree_root is AnimationNodeStateMachine):
		printerr("TEST FAILED: AnimationTree or root state machine missing in AnimatedEnemy.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	var sm_root: AnimationNodeStateMachine = chop_anim_tree.tree_root as AnimationNodeStateMachine
	if not sm_root.has_node(&"MeleeAttack"):
		printerr("TEST FAILED: AnimationTree state machine missing MeleeAttack node.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	var melee_attack_node: AnimationNodeBlendTree = sm_root.get_node(&"MeleeAttack") as AnimationNodeBlendTree
	if melee_attack_node == null:
		printerr("TEST FAILED: MeleeAttack node is not a BlendTree with TimeScale slowdown support.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	var melee_attack_anim: AnimationNodeAnimation = melee_attack_node.get_node(&"Animation") as AnimationNodeAnimation
	if melee_attack_anim == null or melee_attack_anim.animation != &"EnemyAnimations/Melee_2H_Attack_Chop":
		printerr("TEST FAILED: MeleeAttack node does not play EnemyAnimations/Melee_2H_Attack_Chop.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	var melee_attack_timescale: AnimationNodeTimeScale = melee_attack_node.get_node(&"TimeScale") as AnimationNodeTimeScale
	if melee_attack_timescale == null:
		printerr("TEST FAILED: MeleeAttack BlendTree missing TimeScale node for hitstop slowdown.")
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	# Check transitions into and out of MeleeAttack
	var found_in := false
	var found_out := false
	for i: int in sm_root.get_transition_count():
		var from_node: StringName = sm_root.get_transition_from(i)
		var to_node: StringName = sm_root.get_transition_to(i)
		var trans: AnimationNodeStateMachineTransition = sm_root.get_transition(i)
		if from_node == &"WalkSpace" and to_node == &"MeleeAttack":
			if trans.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED:
				found_in = true
		elif from_node == &"MeleeAttack" and to_node == &"WalkSpace":
			if trans.switch_mode == AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END and trans.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO and is_equal_approx(trans.xfade_time, 0.2):
				found_out = true
	if not found_in or not found_out:
		printerr("TEST FAILED: Transitions for MeleeAttack invalid. found_in: ", found_in, " found_out: ", found_out)
		anim_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AnimatedEnemy AnimationPlayer & AnimationTree MeleeAttack state and transitions verified.")
	anim_enemy.queue_free()
	await get_tree().process_frame

	# 3. Verify MeleeEnemy StateMachine wiring & transitions
	var test_melee: Character = melee_scene.instantiate() as Character
	add_child(test_melee)
	await get_tree().physics_frame
	var melee_sm_node: StateMachine = test_melee.get_node_or_null("StateMachine") as StateMachine
	var stun_node: EnemyStun = melee_sm_node.get_node_or_null("EnemyStun") as EnemyStun
	var move_state: EnemyMove = melee_sm_node.get_node_or_null("EnemyMove") as EnemyMove
	var attack_node: CharacterAttack = melee_sm_node.get_node_or_null("EnemyAttack") as CharacterAttack
	var test_melee_ai_sm: AIStateMachine = test_melee.ai_state_machine as AIStateMachine
	var pursue_state: AIPursue = test_melee_ai_sm.get_node_or_null("AIPursue") as AIPursue

	if stun_node == null or stun_node.next_state != move_state:
		printerr("TEST FAILED: EnemyStun.next_state expected EnemyMove, got: ", stun_node.next_state if stun_node else "null")
		test_melee.queue_free()
		get_tree().quit(1)
		return
	if attack_node == null or attack_node.attack_animation_name != "MeleeAttack" or attack_node.next_states.is_empty() or attack_node.next_states[0] != move_state:
		printerr("TEST FAILED: EnemyAttack not configured with attack_animation_name MeleeAttack or next_states EnemyMove.")
		test_melee.queue_free()
		get_tree().quit(1)
		return
	if pursue_state == null or pursue_state.attack_state_name != "EnemyAttack":
		printerr("TEST FAILED: AIPursue.attack_state_name expected EnemyAttack, got: ", pursue_state.attack_state_name if pursue_state else "null")
		test_melee.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy EnemyStun, EnemyMove, EnemyAttack, and AIPursue state wiring verified.")

	# 4. Verify Pursue -> Attack transition on player proximity
	var p_player: Character = load("res://Player/player.tscn").instantiate() as Character
	add_child(p_player)
	p_player.global_position = test_melee.global_position + Vector3(1.5, 0.0, 0.0) # within attack_range (3.0)
	pursue_state.physics_update(0.1)
	await get_tree().process_frame
	if melee_sm_node.state != attack_node:
		printerr("TEST FAILED: AIPursue did not transition body StateMachine to EnemyAttack when in range. Got: ", melee_sm_node.state.name if melee_sm_node.state else "null")
		p_player.queue_free()
		test_melee.queue_free()
		get_tree().quit(1)
		return
	print("AIPursue proximity transition to EnemyAttack verified.")
	p_player.queue_free()
	test_melee.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 30: Melee AttackComponent, Area3D Hitbox & Damage (Lecture 83)
	# ---------------------------------------------------------
	print("\n>>> PART 30: Melee AttackComponent, Area3D Hitbox & Damage")
	var melee_inst: Character = melee_scene.instantiate() as Character
	add_child(melee_inst)
	await get_tree().physics_frame
	await get_tree().process_frame

	# 1. Verify weapon_hitbox export
	if melee_inst.weapon_hitbox == null:
		printerr("TEST FAILED: MeleeEnemy weapon_hitbox export is null.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var hitbox: Area3D = melee_inst.weapon_hitbox
	print("weapon_hitbox assigned: ", hitbox.name)

	# 2. Verify Area3D configuration: shape BoxShape3D
	var hitbox_col_shape: CollisionShape3D = hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if hitbox_col_shape == null or hitbox_col_shape.shape == null or not (hitbox_col_shape.shape is BoxShape3D):
		printerr("TEST FAILED: weapon_hitbox CollisionShape3D is not BoxShape3D.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return

	# 3. Verify weapon visual mesh & material
	var mesh_inst: MeshInstance3D = hitbox.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst == null or not (mesh_inst.mesh is CylinderMesh):
		printerr("TEST FAILED: MeshInstance3D missing under hitbox or not CylinderMesh.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var cyl: CylinderMesh = mesh_inst.mesh as CylinderMesh
	if not is_equal_approx(cyl.top_radius, 0.1) or not is_equal_approx(cyl.bottom_radius, 0.1):
		printerr("TEST FAILED: CylinderMesh radii expected 0.1, got top=", cyl.top_radius, " bottom=", cyl.bottom_radius)
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(mesh_inst.position.y, 1.0):
		printerr("TEST FAILED: MeshInstance3D position.y expected 1.0, got: ", mesh_inst.position.y)
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var mat: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
	if mat == null or mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		printerr("TEST FAILED: MeshInstance3D material_override invalid or not unshaded.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("weapon_hitbox BoxShape3D and cylinder mesh verified.")

	# 4. Verify AttackComponent child
	var att_comp: AttackComponent = hitbox.get_node_or_null("AttackComponent") as AttackComponent
	if att_comp == null or att_comp.shake_on_damage:
		printerr("TEST FAILED: AttackComponent missing under hitbox or shake_on_damage is true.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("Melee AttackComponent verified under hitbox (shake_on_damage = false).")

	# 5. Verify WeaponSlot bone_name is "handslot.r" and hitbox wiring
	var ws: BoneAttachment3D = hitbox.get_parent() as BoneAttachment3D
	if ws == null or ws.bone_name != "handslot.r":
		printerr("TEST FAILED: WeaponSlot bone_name expected handslot.r, got: ", ws.bone_name if ws else "null")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if not (ws is WeaponSlot) or (ws as WeaponSlot).hitbox != hitbox:
		printerr("TEST FAILED: WeaponSlot hitbox export is not wired to Area3D.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if hitbox.monitoring != false:
		printerr("TEST FAILED: Melee hitbox should be disabled by default, got monitoring=true.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	(ws as WeaponSlot).enabled = true
	if hitbox.monitoring != true:
		printerr("TEST FAILED: Setting WeaponSlot.enabled=true did not enable hitbox monitoring.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	(ws as WeaponSlot).enabled = false
	if hitbox.monitoring != false:
		printerr("TEST FAILED: Setting WeaponSlot.enabled=false did not disable hitbox monitoring.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("WeaponSlot bone_name 'handslot.r', hitbox wiring, and enabled toggle verified.")

	# 6. Verify EnemyAttack exports
	var melee_attack_state: CharacterAttack = melee_inst.get_node_or_null("StateMachine/EnemyAttack") as CharacterAttack
	if melee_attack_state == null or melee_attack_state.attack_component != att_comp or not is_equal_approx(melee_attack_state.damage, 8.0):
		printerr("TEST FAILED: EnemyAttack state configuration invalid.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack attack_component and damage (8.0) verified.")

	# 7. Verify RESET animation in animated_enemy
	var anim_enemy_chk: Node3D = load("res://Enemy/animated_enemy.tscn").instantiate() as Node3D
	var ap_chk: AnimationPlayer = anim_enemy_chk.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not ap_chk.has_animation(&"RESET"):
		printerr("TEST FAILED: AnimatedEnemy AnimationPlayer missing RESET animation.")
		anim_enemy_chk.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var reset_anim: Animation = ap_chk.get_animation(&"RESET")
	if reset_anim.get_track_count() == 0 or reset_anim.track_get_key_value(0, 0) != false:
		printerr("TEST FAILED: RESET animation track invalid.")
		anim_enemy_chk.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	anim_enemy_chk.queue_free()
	print("AnimatedEnemy RESET animation keyframes verified.")

	# ---------------------------------------------------------
	# PART 31: Melee Enemy Polish, Exception Reset, Collision Layers & Mixed Spawns (Lecture 84)
	# ---------------------------------------------------------
	print("\n>>> PART 31: Melee Enemy Polish, Exception Reset, Collision Layers & Mixed Spawns")

	# 1. Verify Area3D collision_mask == 64 (Hurtboxes layer only)
	if hitbox.collision_mask != 64:
		printerr("TEST FAILED: Melee weapon hitbox collision_mask expected 64, got: ", hitbox.collision_mask)
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("Melee weapon hitbox collision_mask = 64 (Hurtboxes layer only) verified.")

	# 1b. Verify melee enemy Hurtbox presence, layer isolation, and wiring
	var melee_hurtbox: Hurtbox = melee_inst.get_node_or_null("Hurtbox") as Hurtbox
	if melee_hurtbox == null or melee_hurtbox.collision_layer != 128 or melee_hurtbox.collision_mask != 0:
		printerr("TEST FAILED: MeleeEnemy Hurtbox missing or not isolated (layer 128, mask 0).")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if melee_hurtbox.health_component == null or melee_hurtbox.knockback_component == null:
		printerr("TEST FAILED: MeleeEnemy Hurtbox missing health/knockback wiring.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if melee_hurtbox.get_node_or_null("CollisionShape3D") == null:
		printerr("TEST FAILED: MeleeEnemy Hurtbox missing CollisionShape3D.")
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy Hurtbox (layer 64, wired refs, shape) verified.")

	# 2. Verify EnemyAttack.enter() calls attack_component.reset_exceptions()
	var dummy_col: StaticBody3D = StaticBody3D.new()
	add_child(dummy_col)
	att_comp.temporary_exceptions.append(dummy_col)
	if att_comp.temporary_exceptions.is_empty():
		printerr("TEST FAILED: Failed to add temporary exception to AttackComponent.")
		dummy_col.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	melee_attack_state.enter("EnemyMove")
	if not att_comp.temporary_exceptions.is_empty():
		printerr("TEST FAILED: EnemyAttack.enter() did not clear temporary_exceptions.")
		dummy_col.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	dummy_col.queue_free()
	print("EnemyAttack.enter() attack_component.reset_exceptions() verified.")

	# 3. Verify Player collision_layer == 17 (Layer 1 + Layer 5)
	var player_chk: Character = load("res://Player/player.tscn").instantiate() as Character
	if player_chk == null or player_chk.collision_layer != 17:
		printerr("TEST FAILED: Player collision_layer expected 17, got: ", player_chk.collision_layer if player_chk else "null")
		if player_chk: player_chk.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var player_hurtbox: Hurtbox = player_chk.get_node_or_null("Hurtbox") as Hurtbox
	if player_hurtbox == null or player_hurtbox.collision_layer != 64 or player_hurtbox.collision_mask != 0:
		printerr("TEST FAILED: Player Hurtbox missing or not isolated (layer 64, mask 0).")
		player_chk.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	if player_hurtbox.health_component != player_chk.health_component or player_hurtbox.knockback_component != player_chk.knockback_component:
		printerr("TEST FAILED: Player Hurtbox not wired to player health/knockback components.")
		player_chk.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	player_chk.queue_free()
	print("Player collision_layer = 17 (Layers 1 and 5) verified.")
	print("Player Hurtbox (layer 64, wired refs) verified.")

	# 4. Verify WaveObjective mixed enemy random selection
	var mixed_wave_obj: WaveObjective = WaveObjective.new()
	add_child(mixed_wave_obj)
	await get_tree().process_frame
	if mixed_wave_obj.all_enemies.is_empty():
		printerr("TEST FAILED: WaveObjective all_enemies is empty.")
		mixed_wave_obj.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	for spawned_enemy: Character in mixed_wave_obj.all_enemies:
		if spawned_enemy == null or not (spawned_enemy is Character) or not spawned_enemy.is_in_group("enemy"):
			printerr("TEST FAILED: WaveObjective spawned invalid enemy instance.")
			mixed_wave_obj.queue_free()
			melee_inst.queue_free()
			get_tree().quit(1)
			return
	mixed_wave_obj.queue_free()
	print("WaveObjective mixed enemy template random instantiation verified.")

	# ---------------------------------------------------------
	# PART 32: Enemy KnockbackComponent & Attack Knockback (Lecture 86)
	# ---------------------------------------------------------
	print("\n>>> PART 32: Enemy KnockbackComponent & Attack Knockback")

	# 1. Base Enemy KnockbackComponent verification
	var base_enemy_scene: PackedScene = load("res://Enemy/enemy_base.tscn")
	var base_enemy: Character = base_enemy_scene.instantiate() as Character
	base_enemy.position = Vector3(10.0, 1.0, 10.0)
	add_child(base_enemy)
	base_enemy.velocity = Vector3(0.0, -1.0, 0.0)
	base_enemy.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame
	if base_enemy.knockback_component == null:
		printerr("TEST FAILED: Base Enemy knockback_component is null.")
		base_enemy.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	var enemy_kb: KnockbackComponent = base_enemy.knockback_component
	if not is_equal_approx(enemy_kb.decay, 8.0) or not is_equal_approx(enemy_kb.max_knockback, 50.0):
		printerr("TEST FAILED: Enemy KnockbackComponent decay or max_knockback mismatch.")
		base_enemy.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("Enemy KnockbackComponent onready var & properties verified.")

	# 2. EnemyStun knockback momentum verification
	var enemy_stun_state: EnemyStun = base_enemy.get_node_or_null("StateMachine/EnemyStun") as EnemyStun
	if enemy_stun_state != null:
		enemy_kb.magnitude = Vector3(15.0, 0.0, 0.0)
		enemy_stun_state.physics_update(0.016)
		if not base_enemy.velocity.is_equal_approx(Vector3(15.0, 0.0, 0.0)):
			printerr("TEST FAILED: EnemyStun velocity should match knockback magnitude when active, got: ", base_enemy.velocity)
			base_enemy.queue_free()
			melee_inst.queue_free()
			get_tree().quit(1)
			return
		enemy_kb.magnitude = Vector3.ZERO
		enemy_stun_state.physics_update(0.016)
		if not base_enemy.velocity.is_zero_approx():
			printerr("TEST FAILED: EnemyStun velocity should be zero when inactive, got: ", base_enemy.velocity)
			base_enemy.queue_free()
			melee_inst.queue_free()
			get_tree().quit(1)
			return
		print("EnemyStun physics_update knockback velocity override verified.")
	base_enemy.queue_free()

	# 3. EnemyAttack knockback export (20.0)
	if not is_equal_approx(melee_attack_state.knockback, 20.0):
		printerr("TEST FAILED: EnemyAttack knockback expected 20.0, got: ", melee_attack_state.knockback)
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack knockback export (20.0) verified.")

	# 4. EnemyProjectile knockback export (15.0)
	var kb_proj_scene: PackedScene = load("res://Enemy/enemy_projectile.tscn")
	var test_proj: EnemyProjectile = kb_proj_scene.instantiate() as EnemyProjectile
	if not is_equal_approx(test_proj.knockback, 15.0):
		printerr("TEST FAILED: EnemyProjectile knockback expected 15.0, got: ", test_proj.knockback)
		test_proj.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	test_proj.queue_free()
	print("EnemyProjectile knockback export (15.0) verified.")

	# 5. PlayerAttack knockback export (15.0)
	var player_scene_kb: PackedScene = load("res://Player/player.tscn")
	var test_player_kb: Character = player_scene_kb.instantiate() as Character
	var player_attack1: CharacterAttack = test_player_kb.get_node_or_null("StateMachine/PlayerAttack") as CharacterAttack
	if player_attack1 == null or not is_equal_approx(float(player_attack1.get("knockback")), 15.0):
		printerr("TEST FAILED: PlayerAttack knockback expected 15.0, got: ", player_attack1.get("knockback") if player_attack1 else "null")
		test_player_kb.queue_free()
		melee_inst.queue_free()
		get_tree().quit(1)
		return
	test_player_kb.queue_free()
	print("PlayerAttack knockback export (15.0) verified.")

	melee_inst.queue_free()
	await get_tree().process_frame

	# >>> PART 33: Falling Enemies, EnemyFall State & Run Reset Polish <<<
	print("\n>>> PART 33: EnemyFall State, Fall Transitions & Polish")
	var base_enemy_scene_p33: PackedScene = load("res://Enemy/enemy_base.tscn")
	var base_enemy_inst_p33: Character = base_enemy_scene_p33.instantiate() as Character
	add_child(base_enemy_inst_p33)
	
	var p33_sm: Node = base_enemy_inst_p33.get_node("StateMachine")
	var p33_fall: EnemyFall = p33_sm.get_node_or_null("EnemyFall") as EnemyFall
	if p33_fall == null:
		printerr("TEST FAILED: EnemyFall node not found in enemy.tscn")
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyFall node in enemy.tscn verified.")
	
	if p33_fall.land_state != p33_sm.get_node("EnemyStun"):
		printerr("TEST FAILED: EnemyFall.land_state is not wired to EnemyStun.")
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyFall.land_state wired to EnemyStun verified.")
	
	if p33_fall.character != base_enemy_inst_p33:
		printerr("TEST FAILED: EnemyFall.character is not wired to base Character.")
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyFall.character wiring verified.")
	
	# Verify fall_state wired on EnemyMove, EnemyStun, EnemyDefeat
	var p33_move: CharacterState = p33_sm.get_node("EnemyMove") as CharacterState
	var p33_stun: CharacterState = p33_sm.get_node("EnemyStun") as CharacterState
	var p33_defeat: CharacterState = p33_sm.get_node("EnemyDefeat") as CharacterState
	if p33_move.fall_state != p33_fall or p33_stun.fall_state != p33_fall or p33_defeat.fall_state != p33_fall:
		printerr("TEST FAILED: fall_state is not wired to EnemyFall on EnemyMove, EnemyStun, or EnemyDefeat.")
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("fall_state on EnemyMove, EnemyStun, and EnemyDefeat wired to EnemyFall verified.")
	
	# Verify melee_enemy.tscn wiring
	var melee_scene_p33: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var melee_inst_p33: Character = melee_scene_p33.instantiate() as Character
	var melee_sm_p33: Node = melee_inst_p33.get_node("StateMachine")
	var melee_fall_p33: CharacterState = melee_sm_p33.get_node("EnemyFall") as CharacterState
	var melee_move_p33: CharacterState = melee_sm_p33.get_node("EnemyMove") as CharacterState
	var melee_attack_p33: CharacterState = melee_sm_p33.get_node("EnemyAttack") as CharacterState
	if melee_move_p33.fall_state != melee_fall_p33 or melee_attack_p33.fall_state != melee_fall_p33:
		printerr("TEST FAILED: fall_state on EnemyMove or EnemyAttack in melee_enemy.tscn not wired to EnemyFall.")
		base_enemy_inst_p33.queue_free()
		melee_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("MeleeEnemy EnemyMove & EnemyAttack fall_state wiring verified.")
	melee_inst_p33.queue_free()
	
	# Verify ranged_enemy.tscn wiring
	var ranged_scene_p33: PackedScene = load("res://Enemy/ranged_enemy.tscn")
	var ranged_inst_p33: Character = ranged_scene_p33.instantiate() as Character
	var ranged_sm_p33: Node = ranged_inst_p33.get_node("StateMachine")
	var ranged_fall_p33: CharacterState = ranged_sm_p33.get_node("EnemyFall") as CharacterState
	var ranged_move_p33: CharacterState = ranged_sm_p33.get_node("EnemyMove") as CharacterState
	var ranged_attack_p33: CharacterState = ranged_sm_p33.get_node("EnemyAttack") as CharacterState
	if ranged_move_p33.fall_state != ranged_fall_p33 or ranged_attack_p33.fall_state != ranged_fall_p33:
		printerr("TEST FAILED: fall_state on EnemyMove or EnemyAttack in ranged_enemy.tscn not wired to EnemyFall.")
		base_enemy_inst_p33.queue_free()
		ranged_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy EnemyMove & EnemyAttack fall_state wiring verified.")
	ranged_inst_p33.queue_free()
	
	# Verify EnemyFall.physics_update() sets velocity to gravity
	p33_fall.physics_update(0.1)
	if base_enemy_inst_p33.velocity != base_enemy_inst_p33.get_gravity():
		printerr("TEST FAILED: EnemyFall.physics_update did not set velocity to get_gravity(). Got: ", base_enemy_inst_p33.velocity)
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyFall.physics_update gravity velocity verified.")
	
	# Verify CharacterState.core_movement() emits fall_state when not on floor
	var state_transitioned := {"target": ""}
	p33_move.finished.connect(func(next: String) -> void: state_transitioned["target"] = next)
	p33_move.core_movement(0.1, base_enemy_inst_p33.movement_speed, Vector3(1, 0, 0))
	if state_transitioned["target"] != "EnemyFall":
		printerr("TEST FAILED: core_movement did not emit EnemyFall when not on floor. Got: ", state_transitioned["target"])
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyState.core_movement floor check and fall transition verified.")
	
	# Verify EnemyStun.physics_update() emits fall_state when not on floor
	state_transitioned["target"] = ""
	p33_stun.finished.connect(func(next: String) -> void: state_transitioned["target"] = next)
	p33_stun.physics_update(0.1)
	if state_transitioned["target"] != "EnemyFall":
		printerr("TEST FAILED: EnemyStun.physics_update did not emit EnemyFall when not on floor. Got: ", state_transitioned["target"])
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("EnemyStun.physics_update floor check and fall transition verified.")
	
	# Verify UpgradeIcon button group
	var upgrade_scene_p33: PackedScene = load("res://UserInterface/upgrade_icon.tscn")
	var upgrade_inst_p33: UpgradeIcon = upgrade_scene_p33.instantiate() as UpgradeIcon
	add_child(upgrade_inst_p33)
	var tb_p33: TextureButton = upgrade_inst_p33.get_node("TextureButton") as TextureButton
	if not tb_p33.is_in_group("upgrade_button"):
		printerr("TEST FAILED: TextureButton in upgrade_icon.tscn is not in 'upgrade_button' group.")
		upgrade_inst_p33.queue_free()
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeIcon TextureButton 'upgrade_button' group membership verified.")
	
	# Verify take_upgrade() disables group
	upgrade_inst_p33.take_upgrade()
	if not tb_p33.disabled:
		printerr("TEST FAILED: take_upgrade did not disable the button via call_group.")
		upgrade_inst_p33.queue_free()
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("take_upgrade call_group disable verified.")
	upgrade_inst_p33.queue_free()
	
	# Verify Player.reset_game_state() resets ProgressionState.difficulty_level = 1
	var player_scene_p33: PackedScene = load("res://Player/player.tscn")
	var player_inst_p33: Character = player_scene_p33.instantiate() as Character
	ProgressionState.difficulty_level = 5
	player_inst_p33.reset_game_state()
	if ProgressionState.difficulty_level != 1:
		printerr("TEST FAILED: reset_game_state did not reset difficulty_level to 1. Got: ", ProgressionState.difficulty_level)
		player_inst_p33.queue_free()
		base_enemy_inst_p33.queue_free()
		get_tree().quit(1)
		return
	print("Player.reset_game_state resetting difficulty_level = 1 verified.")
	player_inst_p33.queue_free()
	base_enemy_inst_p33.queue_free()

	# ---------------------------------------------------------
	# PART 34: Melee Team Filtering & Dead-Target Rejection
	# ---------------------------------------------------------
	print("\n>>> PART 34: Melee Team Filtering & Dead-Target Rejection")
	var team_attacker: Character = melee_scene_p33.instantiate() as Character
	var team_enemy_target: Character = melee_scene_p33.instantiate() as Character
	var team_player_target: Character = player_scene_p33.instantiate() as Character
	add_child(team_attacker)
	add_child(team_enemy_target)
	add_child(team_player_target)
	# Zero body layers so Jolt depenetration never shoves the stacked bodies apart
	# (area detection uses separate layers and is unaffected).
	for c: Character in [team_attacker, team_enemy_target, team_player_target]:
		c.collision_layer = 0
		c.collision_mask = 0
	await get_tree().physics_frame
	(team_attacker.get_node("AIStateMachine") as Node).set_physics_process(false)
	(team_enemy_target.get_node("AIStateMachine") as Node).set_physics_process(false)
	# Freeze the attacker's animation tree so its WeaponSlot tracks stop forcing
	# monitoring off while the hitbox is manually activated below.
	team_attacker.animation_tree.active = false
	team_attacker.global_position = Vector3(0.0, 1.0, 60.0)
	await get_tree().physics_frame

	# Stack both targets on the hitbox center so overlap is guaranteed.
	var team_hitbox_early: Area3D = team_attacker.weapon_hitbox
	team_enemy_target.global_position = team_hitbox_early.global_position
	team_player_target.global_position = team_hitbox_early.global_position
	await get_tree().physics_frame

	# Player hitbox must mask enemy hurtboxes only; projectile keeps walls + both teams.
	var player_hitbox_p34: Area3D = team_player_target.get_node("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/HitboxArea") as Area3D
	var proj_scene_p34: PackedScene = load("res://Enemy/enemy_projectile.tscn") as PackedScene
	var proj_probe_p34: Area3D = proj_scene_p34.instantiate() as Area3D
	if player_hitbox_p34 == null or player_hitbox_p34.collision_mask != 128:
		printerr("TEST FAILED: Player hitbox must mask enemy hurtboxes only (128).")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		proj_probe_p34.queue_free()
		get_tree().quit(1)
		return
	if proj_probe_p34.collision_mask != 193:
		printerr("TEST FAILED: Projectile must mask walls + both hurtbox layers (193). Got: ", proj_probe_p34.collision_mask)
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		proj_probe_p34.queue_free()
		get_tree().quit(1)
		return
	proj_probe_p34.queue_free()
	print("Hitbox team masks verified (player 128, projectile 193).")

	# Activate the melee hitbox with all three bodies overlapping it.
	var team_hitbox: Area3D = team_attacker.weapon_hitbox
	var team_att: AttackComponent = team_hitbox.get_node_or_null("AttackComponent") as AttackComponent
	team_att.damage = 8.0
	team_att.reset_exceptions()
	(team_hitbox.get_parent() as WeaponSlot).enabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if team_hitbox.get_overlapping_areas().is_empty():
		printerr("TEST FAILED: No hurtbox overlaps hitbox (test setup invalid).")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	var enemy_health_p34: HealthComponent = team_enemy_target.get_node("HealthComponent") as HealthComponent
	if not is_equal_approx(enemy_health_p34.current_health, enemy_health_p34.max_health):
		printerr("TEST FAILED: Melee enemy damaged another enemy (friendly fire). Health: ", enemy_health_p34.current_health)
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	print("Melee friendly-fire blocked verified (enemy health unchanged).")
	var player_health_p34: HealthComponent = team_player_target.get_node("HealthComponent") as HealthComponent
	if player_health_p34.current_health >= player_health_p34.max_health:
		printerr("TEST FAILED: Melee enemy did not damage the player.")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	print("Melee enemy still damages player verified.")

	# Dead targets must reject hits.
	var enemy_hurtbox_p34: Hurtbox = team_enemy_target.get_node("Hurtbox") as Hurtbox
	enemy_health_p34.take_damage(9999.0)
	await get_tree().physics_frame
	var health_after_kill: float = enemy_health_p34.current_health
	team_att.reset_exceptions()
	if enemy_hurtbox_p34.receive_hit(8.0, Vector3.ZERO):
		printerr("TEST FAILED: Dead enemy accepted receive_hit.")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	if team_att.deal_damage_to(enemy_hurtbox_p34, 8.0, Vector3.ZERO):
		printerr("TEST FAILED: deal_damage_to damaged a dead enemy.")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(enemy_health_p34.current_health, health_after_kill):
		printerr("TEST FAILED: Dead enemy health changed after rejected hits.")
		team_attacker.queue_free()
		team_enemy_target.queue_free()
		team_player_target.queue_free()
		get_tree().quit(1)
		return
	print("Dead-target hit rejection verified.")
	team_attacker.queue_free()
	team_enemy_target.queue_free()
	team_player_target.queue_free()
	await get_tree().physics_frame

	# ---------------------------------------------------------
	# PART 35: Projectile Corpse Penetration & Hurtbox Deactivation
	# ---------------------------------------------------------
	print("\n>>> PART 35: Projectile Corpse Penetration & Hurtbox Deactivation")
	var corpse_enemy: Character = melee_scene_p33.instantiate() as Character
	add_child(corpse_enemy)
	corpse_enemy.global_position = Vector3(0.0, 1.0, 50.0)
	(corpse_enemy.get_node("AIStateMachine") as Node).set_physics_process(false)
	var corpse_hurtbox: Hurtbox = corpse_enemy.get_node_or_null("Hurtbox") as Hurtbox
	var corpse_shape: CollisionShape3D = corpse_hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if corpse_hurtbox == null or corpse_shape == null:
		printerr("TEST FAILED: Melee enemy Hurtbox or CollisionShape3D missing.")
		corpse_enemy.queue_free()
		get_tree().quit(1)
		return
	if not corpse_hurtbox.is_alive():
		printerr("TEST FAILED: Hurtbox.is_alive() was false for living enemy.")
		corpse_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Hurtbox.is_alive() true on alive enemy verified.")

	# Defeat enemy to make it a corpse
	corpse_enemy.health_component.take_damage(9999.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if corpse_hurtbox.is_alive():
		printerr("TEST FAILED: Hurtbox.is_alive() is true for defeated enemy.")
		corpse_enemy.queue_free()
		get_tree().quit(1)
		return
	if corpse_hurtbox.monitorable or corpse_hurtbox.monitoring:
		printerr("TEST FAILED: Hurtbox monitoring/monitorable not disabled on defeat.")
		corpse_enemy.queue_free()
		get_tree().quit(1)
		return
	if not corpse_shape.disabled:
		printerr("TEST FAILED: Hurtbox CollisionShape3D not disabled on defeat.")
		corpse_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Hurtbox disabled and is_alive() false on corpse verified.")

	# Instantiate living player target behind the corpse
	var living_target: Character = player_scene_p33.instantiate() as Character
	add_child(living_target)
	living_target.global_position = Vector3(0.0, 1.0, 60.0)
	await get_tree().physics_frame

	# Instantiate projectile directly on top of corpse
	var corpse_proj: EnemyProjectile = proj_scene_p34.instantiate() as EnemyProjectile
	add_child(corpse_proj)
	corpse_proj.global_position = corpse_enemy.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame

	if corpse_proj.is_queued_for_deletion():
		printerr("TEST FAILED: EnemyProjectile detonated on corpse!")
		corpse_proj.queue_free()
		corpse_enemy.queue_free()
		living_target.queue_free()
		get_tree().quit(1)
		return
	print("EnemyProjectile ignored corpse verified (did not detonate).")

	# Move projectile onto living target to verify it still hits live entities
	var target_initial_hp: float = living_target.health_component.current_health
	corpse_proj.global_position = living_target.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame

	var proj_destroyed: bool = not is_instance_valid(corpse_proj) or corpse_proj.is_queued_for_deletion()
	if not proj_destroyed:
		printerr("TEST FAILED: EnemyProjectile did not detonate on living target.")
		corpse_proj.queue_free()
		corpse_enemy.queue_free()
		living_target.queue_free()
		get_tree().quit(1)
		return
	if living_target.health_component.current_health >= target_initial_hp:
		printerr("TEST FAILED: Living target took no damage from projectile.")
		corpse_enemy.queue_free()
		living_target.queue_free()
		get_tree().quit(1)
		return
	print("EnemyProjectile hit living target after ignoring corpse verified.")

	if is_instance_valid(corpse_proj):
		corpse_proj.queue_free()
	corpse_enemy.queue_free()
	living_target.queue_free()
	await get_tree().physics_frame

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
	print("  13. EnemyProjectile scene, movement, and RangedEnemy fire verified")
	print("  14. Mesh mount export & Player group lookup verified              ")
	print("  15. look_at_player model-front aiming verified                    ")
	print("  16. Projectile lifetime Timer, collision cleanup & damage verified")
	print("  17. NavigationAgent3D & LevelTemplate NavigationMesh (Baked) ok   ")
	print("  18. NavigationServer3D map_get_random_point verified              ")
	print("  19. SceneTransition singleton & fade methods verified             ")
	print("  20. Player state & health preservation across levels verified     ")
	print("  21. Level 1 inherited scene, geometry, and placement verified     ")
	print("  22. Level 2 inherited scene, litter props, and navmesh verified   ")
	print("  23. Level 3 inherited scene, litter props, and navmesh verified   ")
	print("  24. Level shuffling & difficulty curve enemy scaling verified     ")
	print("  25. UpgradeShop dynamic random selection (GlobalVars.upgrades) & exit ok")
	print("  26. Window scaling & ui_toggle_fullscreen autoload verified       ")
	print("  27. Base UpgradeIcon scene, styling, and UpgradeShop placement ok ")
	print("  28. MeleeEnemy scene, StateMachine & EnemyPursue state verified   ")
	print("  29. Melee Attack, AnimationTree & Pursue Transition verified      ")
	print("  30. Melee AttackComponent, Area3D Hitbox & Damage verified        ")
	print("  31. Melee Polish, Exceptions Reset, Layers & Mixed Spawns verified")
	print("  32. Enemy KnockbackComponent, EnemyStun & Attack Knockback verified")
	print("  33. Falling Enemies, EnemyFall State & Run Reset Polish verified  ")
	print("  34. Melee team filtering & dead-target rejection verified        ")
	print("  35. Projectile corpse penetration & hurtbox deactivation verified ")
	print("====================================================================")
	
	get_tree().quit(0)


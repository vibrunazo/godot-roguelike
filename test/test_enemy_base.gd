extends Node

const TestUtils = preload("res://test/test_utils.gd")
const UpgradeIcon = preload("res://UserInterface/upgrade_icon.gd")
const UpgradeHealth = preload("res://UserInterface/upgrade_health.gd")

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
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
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
	
	if wave_obj.all_enemies.size() != GlobalVars.get_enemy_count():
		printerr("TEST FAILED: WaveObjective all_enemies size is ", wave_obj.all_enemies.size(), ", expected ", GlobalVars.get_enemy_count())
		level.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective all_enemies size (", wave_obj.all_enemies.size(), ") matches GlobalVars.get_enemy_count() verified.")

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
	var valid_paths: Array[String] = ["res://Levels/LevelTemplate.tscn", "uid://dyj3auoai18wd", ""]
	if not exit_point.next_scene_path in valid_paths or not exit_point.next_level_path in valid_paths:
		printerr("TEST FAILED: ExitPoint next_scene_path: '", exit_point.next_scene_path, "', next_level_path: '", exit_point.next_level_path, "'")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint initially invisible, locked, and next_scene_path export var verified.")

	# Verify difficulty curve and GlobalVars enemy count
	var curve_res: Curve = load("res://Singletons/difficulty_curve.tres") as Curve
	if curve_res == null or curve_res.point_count < 2:
		printerr("TEST FAILED: difficulty_curve.tres missing or invalid point count.")
		level.queue_free()
		get_tree().quit(1)
		return
	if GlobalVars.get_enemy_count() < 3:
		printerr("TEST FAILED: GlobalVars.get_enemy_count() at level 1 is ", GlobalVars.get_enemy_count(), ", expected >= 3.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Difficulty curve and GlobalVars.get_enemy_count() (level 1: ", GlobalVars.get_enemy_count(), ") verified.")

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
	var cached_player: Player = cached_player_scene.instantiate() as Player
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

	var level_enemy: Enemy = TestUtils.find_enemy(level)
	if level_enemy == null:
		printerr("TEST FAILED: No Enemy subclass instance found via TestUtils in LevelTemplate scene.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy instance found in LevelTemplate via WaveObjective: ", level_enemy.name)
	
	var level_enemy_health: HealthComponent = level_enemy.get_node_or_null("HealthComponent") as HealthComponent
	if level_enemy_health == null or level_enemy_health.max_health != 40.0:
		printerr("TEST FAILED: LevelTemplate Enemy HealthComponent missing or invalid max_health.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("LevelTemplate Enemy HealthComponent confirmed with 40 max health.")

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
	
	var ranged_wait: EnemyWait = ranged_enemy.get_node_or_null("StateMachine/EnemyWait") as EnemyWait
	if ranged_wait == null:
		printerr("TEST FAILED: EnemyWait node missing under RangedEnemy StateMachine.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyWait node verified under RangedEnemy StateMachine.")
	
	if ranged_wait.next_state != ranged_attack:
		printerr("TEST FAILED: EnemyWait.next_state does not point to EnemyAttack. Got: ", ranged_wait.next_state)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyWait.next_state -> EnemyAttack verified.")
	
	# Verify EnemyMeander node and initial state
	var ranged_meander: EnemyMeander = ranged_enemy.get_node_or_null("StateMachine/EnemyMeander") as EnemyMeander
	if ranged_meander == null:
		printerr("TEST FAILED: EnemyMeander node missing under RangedEnemy StateMachine.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander node verified under RangedEnemy StateMachine.")
	
	if ranged_meander.enemy != ranged_enemy:
		printerr("TEST FAILED: EnemyMeander.enemy does not point to RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander.enemy reference verified.")
	
	if ranged_meander.attack_state != ranged_attack:
		printerr("TEST FAILED: EnemyMeander.attack_state does not point to EnemyAttack. Got: ", ranged_meander.attack_state)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander.attack_state -> EnemyAttack verified.")
	
	if not is_equal_approx(ranged_meander.attack_range, 4.0):
		printerr("TEST FAILED: EnemyMeander.attack_range expected 4.0, got: ", ranged_meander.attack_range)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander.attack_range (4.0) verified.")
	
	if ranged_attack.next_state.size() != 2 or not ranged_attack.next_state.has(ranged_wait) or not ranged_attack.next_state.has(ranged_meander):
		printerr("TEST FAILED: EnemyAttack.next_state array is improper: ", ranged_attack.next_state)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyAttack.next_state array [EnemyWait, EnemyMeander] verified.")
	
	if not ranged_enemy.navigation_agent_3d.debug_enabled:
		printerr("TEST FAILED: RangedEnemy NavigationAgent3D.debug_enabled is false.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy NavigationAgent3D.debug_enabled verified as true.")
	
	var ranged_sm: StateMachine = ranged_enemy.get_node_or_null("StateMachine") as StateMachine
	if ranged_sm.state != ranged_meander:
		printerr("TEST FAILED: RangedEnemy initial state is not EnemyMeander. Got: ", ranged_sm.state.name)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy initially in EnemyMeander state.")
	
	# Verify EnemyMeander enter() sets WalkSpace and blend_target = 1.0
	if not is_equal_approx(ranged_enemy.animation_tree.blend_target, 1.0):
		printerr("TEST FAILED: EnemyMeander did not set animation_tree.blend_target to 1.0. Got: ", ranged_enemy.animation_tree.blend_target)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander enter() set blend_target = 1.0 verified.")
	
	# Verify distance_to_player() calculation and attack transition
	var test_player_inst: Player = load("res://Player/player.tscn").instantiate() as Player
	test_player_inst.add_to_group("player")
	add_child(test_player_inst)
	ranged_enemy.player = test_player_inst
	ranged_enemy.global_position = Vector3(0, 0, 0)
	test_player_inst.global_position = Vector3(3, 0, 0)
	if not is_equal_approx(ranged_enemy.distance_to_player(), 3.0):
		printerr("TEST FAILED: distance_to_player() expected 3.0, got: ", ranged_enemy.distance_to_player())
		test_player_inst.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("distance_to_player() verified.")
	
	# Proximity check triggers transition to EnemyAttack
	ranged_meander.physics_update(0.016)
	await get_tree().process_frame
	if ranged_sm.state != ranged_attack:
		printerr("TEST FAILED: EnemyMeander did not transition to EnemyAttack when distance <= attack_range. Got: ", ranged_sm.state.name)
		test_player_inst.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("EnemyMeander proximity attack trigger verified.")
	test_player_inst.queue_free()
	
	# Verify EnemyAttack transitions back randomly to EnemyWait or EnemyMeander via end_attack
	ranged_attack.end_attack("RangedAttack")
	await get_tree().process_frame
	if ranged_sm.state != ranged_wait and ranged_sm.state != ranged_meander:
		printerr("TEST FAILED: end_attack() did not transition RangedEnemy to EnemyWait or EnemyMeander. Got: ", ranged_sm.state.name)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy transitioned to random next state (", ranged_sm.state.name, ") successfully via end_attack()!")
	
	# Verify EnemyWait transitions to EnemyAttack via end_wait
	ranged_sm.state = ranged_wait
	ranged_wait.end_wait()
	await get_tree().process_frame
	if ranged_sm.state != ranged_attack:
		printerr("TEST FAILED: end_wait() did not transition RangedEnemy to EnemyAttack. Got: ", ranged_sm.state.name)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy transitioned to EnemyAttack successfully via end_wait()!")
	
	ranged_enemy.queue_free()
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
	var proj_audio: AudioStreamPlayer3D = proj.get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if proj_audio == null or not proj_audio.autoplay or proj_audio.bus != &"SFX":
		printerr("TEST FAILED: EnemyProjectile AudioStreamPlayer3D improperly configured.")
		get_tree().quit(1)
		return
	print("EnemyProjectile scene & audio verified.")

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
	var test_player: Player = player_scene.instantiate() as Player
	if not test_player.is_in_group("player"):
		printerr("TEST FAILED: Player is not in group 'player'.")
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("Player group 'player' verified.")

	# Add player to tree at an offset position (e.g. at (5, 0, 0))
	add_child(test_player)
	test_player.global_position = Vector3(5.0, 0.0, 0.0)

	var shooter: RangedEnemy = ranged_scene.instantiate() as RangedEnemy
	add_child(shooter)
	shooter.global_position = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().process_frame

	if shooter.player != test_player:
		printerr("TEST FAILED: shooter.player did not resolve test_player from group 'player'.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("shooter.player successfully found Player via group.")

	if shooter.attack_bone == null:
		printerr("TEST FAILED: RangedEnemy attack_bone is null.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy attack_bone assigned: ", shooter.attack_bone.name)

	# Test look_at_player on EnemyWait
	var shooter_wait: EnemyWait = shooter.get_node_or_null("StateMachine/EnemyWait") as EnemyWait
	shooter_wait.look_at_player()
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
	print("look_at_player oriented mesh_mount towards player (dot: ", facing_dir.dot(expected_dir), ") verified.")


	# Test projectile spawned matches mesh_mount global_rotation.y
	shooter._on_weapon_slot_ranged_attack()
	var spawned_proj: EnemyProjectile = null
	for c: Node in shooter.get_children():
		if c is EnemyProjectile:
			spawned_proj = c as EnemyProjectile
			break
	if spawned_proj == null:
		printerr("TEST FAILED: shooter did not spawn EnemyProjectile.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(spawned_proj.global_rotation.y, shooter.mesh_mount.global_rotation.y):
		printerr("TEST FAILED: Spawned projectile rotation.y does not match mesh_mount.global_rotation.y.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("Spawned projectile rotation.y matches mesh_mount.global_rotation.y verified.")

	# Verify position matched attack_bone
	if not spawned_proj.global_position.is_equal_approx(shooter.attack_bone.global_position):
		printerr("TEST FAILED: Spawned projectile position does not match attack_bone.")
		shooter.queue_free()
		test_player.queue_free()
		get_tree().quit(1)
		return
	print("Spawned projectile position matches attack_bone.")

	# Test projectile collision & damage dealing
	var target_health: HealthComponent = test_player.get_node_or_null("HealthComponent") as HealthComponent
	var initial_health: float = target_health.current_health
	# Place projectile directly at test_player to trigger shapecast collision
	var hit_proj: EnemyProjectile = proj_scene.instantiate() as EnemyProjectile
	add_child(hit_proj)
	hit_proj.global_position = test_player.global_position
	await get_tree().physics_frame
	# Run physics process on projectile
	hit_proj._physics_process(0.016)
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
	print("Projectile deleted on collision (is_colliding() -> queue_free()) verified.")

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
	var shop_scene: PackedScene = load("res://UserInterface/UpgradeShop.tscn") as PackedScene
	if shop_scene == null:
		printerr("TEST FAILED: Failed to load res://UserInterface/UpgradeShop.tscn")
		get_tree().quit(1)
		return
	var shop: Control = shop_scene.instantiate() as Control
	if shop == null:
		printerr("TEST FAILED: UpgradeShop root is not a Control node.")
		get_tree().quit(1)
		return
	add_child(shop)

	var shop_script: Script = shop.get_script() as Script
	if shop_script == null or shop_script.resource_path != "res://UserInterface/upgrade_shop.gd":
		printerr("TEST FAILED: UpgradeShop script is not res://UserInterface/upgrade_shop.gd")
		shop.queue_free()
		get_tree().quit(1)
		return

	var bg_rect: ColorRect = shop.get_node_or_null("ColorRect") as ColorRect
	if bg_rect == null or not (bg_rect.material is ShaderMaterial):
		printerr("TEST FAILED: UpgradeShop ColorRect or ShaderMaterial missing.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var shop_material: ShaderMaterial = bg_rect.material as ShaderMaterial
	if shop_material.shader == null or shop_material.get_shader_parameter("NoiseTexture") == null or shop_material.get_shader_parameter("GradientTexture") == null:
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
	if margin_container.get_theme_constant("margin_left") != 128 or margin_container.get_theme_constant("margin_top") != 128 or margin_container.get_theme_constant("margin_right") != 128 or margin_container.get_theme_constant("margin_bottom") != 128:
		printerr("TEST FAILED: UpgradeShop MarginContainer margins are not 128.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var vbox: VBoxContainer = margin_container.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		printerr("TEST FAILED: UpgradeShop VBoxContainer missing.")
		shop.queue_free()
		get_tree().quit(1)
		return

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

	var shop_upgrade_speed: UpgradeIcon = hbox.get_node_or_null("UpgradeSpeed") as UpgradeIcon
	if shop_upgrade_speed == null or shop_upgrade_speed.size_flags_horizontal != 6:
		printerr("TEST FAILED: UpgradeShop UpgradeSpeed instance missing or size_flags_horizontal != 6.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var shop_upgrade_damage: UpgradeIcon = hbox.get_node_or_null("UpgradeDamage") as UpgradeIcon
	if shop_upgrade_damage == null or shop_upgrade_damage.size_flags_horizontal != 6:
		printerr("TEST FAILED: UpgradeShop UpgradeDamage instance missing or size_flags_horizontal != 6.")
		shop.queue_free()
		get_tree().quit(1)
		return

	var shop_upgrade_health: UpgradeIcon = hbox.get_node_or_null("UpgradeHealth") as UpgradeIcon
	if shop_upgrade_health == null or shop_upgrade_health.size_flags_horizontal != 6:
		printerr("TEST FAILED: UpgradeShop UpgradeHealth instance missing or size_flags_horizontal != 6.")
		shop.queue_free()
		get_tree().quit(1)
		return
	if (shop_upgrade_health.get("health_bonus") as float) != 2000.0:
		printerr("TEST FAILED: UpgradeShop UpgradeHealth health_bonus expected 2000.0, got: ", shop_upgrade_health.get("health_bonus"))
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop HBoxContainer, UpgradeSpeed, UpgradeDamage, and UpgradeHealth children verified.")

	# Verify upgrade_container onready reference
	if shop.upgrade_container != hbox:
		printerr("TEST FAILED: UpgradeShop upgrade_container does not match HBoxContainer.")
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop upgrade_container onready reference verified.")

	# Verify each child's upgrade_taken signal is connected to shop.exit_shop
	for child: Node in shop.upgrade_container.get_children():
		var icon: UpgradeIcon = child as UpgradeIcon
		if icon == null:
			printerr("TEST FAILED: Child of upgrade_container is not an UpgradeIcon.")
			shop.queue_free()
			get_tree().quit(1)
			return
		if not icon.upgrade_taken.is_connected(shop.exit_shop):
			printerr("TEST FAILED: UpgradeIcon ", icon.name, " upgrade_taken signal is not connected to exit_shop.")
			shop.queue_free()
			get_tree().quit(1)
			return
	print("UpgradeShop all child upgrade_taken signals connected to exit_shop verified.")

	# Verify exiting_shop guard
	if shop.exiting_shop:
		printerr("TEST FAILED: UpgradeShop exiting_shop should initially be false.")
		shop.queue_free()
		get_tree().quit(1)
		return

	shop.exit_shop(shop_upgrade_speed)
	if not shop.exiting_shop:
		printerr("TEST FAILED: UpgradeShop exiting_shop was not set to true after exit_shop.")
		shop.queue_free()
		get_tree().quit(1)
		return
	print("UpgradeShop exit_shop execution and exiting_shop flag verified.")

	shop.queue_free()

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
	if key_event == null or (key_event.physical_keycode != KEY_F and key_event.keycode != KEY_F):
		printerr("TEST FAILED: ui_toggle_fullscreen event is not KEY_F. physical_keycode: ", key_event.physical_keycode, " keycode: ", key_event.keycode)
		get_tree().quit(1)
		return
	print("InputMap ui_toggle_fullscreen with KEY_F verified.")

	if not GlobalVars.has_method("toggle_fullscreen") or not GlobalVars.has_method("is_fullscreen") or not GlobalVars.has_method("go_fullscreen"):
		printerr("TEST FAILED: GlobalVars missing toggle_fullscreen / is_fullscreen / go_fullscreen methods")
		get_tree().quit(1)
		return
	GlobalVars.toggle_fullscreen()
	print("GlobalVars.toggle_fullscreen() executed successfully.")

	var fs_action_event := InputEventAction.new()
	fs_action_event.action = "ui_toggle_fullscreen"
	fs_action_event.pressed = true
	GlobalVars._unhandled_key_input(fs_action_event)
	print("GlobalVars._unhandled_key_input with ui_toggle_fullscreen verified.")

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

	# Test UpgradeSpeed scene
	var speed_scene: PackedScene = load("res://UserInterface/upgrade_speed.tscn")
	if speed_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_speed.tscn")
		get_tree().quit(1)
		return
	var speed_icon: UpgradeIcon = speed_scene.instantiate() as UpgradeIcon
	if speed_icon == null:
		printerr("TEST FAILED: UpgradeSpeed is not an instance of UpgradeIcon")
		get_tree().quit(1)
		return
	if speed_icon.stat_name != "movement_speed" or speed_icon.stat_bonus != 1.5:
		printerr("TEST FAILED: UpgradeSpeed stat_name or stat_bonus incorrect. Got: ", speed_icon.stat_name, ", ", speed_icon.stat_bonus)
		get_tree().quit(1)
		return
	if speed_icon.text_template != "%.1f -> [color=\"7fffd4\"]%.1f[/color] m/s":
		printerr("TEST FAILED: UpgradeSpeed text_template incorrect: ", speed_icon.text_template)
		get_tree().quit(1)
		return

	# Test player speed upgrade functionality
	var player_scene_upgrade: PackedScene = load("res://Player/player.tscn")
	var upgrade_player: Player = player_scene_upgrade.instantiate() as Player
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

	# Test UpgradeDamage scene
	var damage_scene: PackedScene = load("res://UserInterface/upgrade_damage.tscn")
	if damage_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_damage.tscn")
		get_tree().quit(1)
		return
	var damage_icon: UpgradeIcon = damage_scene.instantiate() as UpgradeIcon
	if damage_icon == null:
		printerr("TEST FAILED: UpgradeDamage is not an instance of UpgradeIcon")
		get_tree().quit(1)
		return
	if damage_icon.stat_name != "damage_stat" or damage_icon.stat_bonus != 50.0:
		printerr("TEST FAILED: UpgradeDamage stat_name or stat_bonus incorrect. Got: ", damage_icon.stat_name, ", ", damage_icon.stat_bonus)
		get_tree().quit(1)
		return
	if damage_icon.text_template != "%d%% -> [color='7fffd4']%d%%[/color] damage":
		printerr("TEST FAILED: UpgradeDamage text_template incorrect: ", damage_icon.text_template)
		get_tree().quit(1)
		return

	# Test player damage upgrade functionality
	var player_scene_dmg: PackedScene = load("res://Player/player.tscn")
	var dmg_player: Player = player_scene_dmg.instantiate() as Player
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

	# Test UpgradeHealth scene
	var health_scene: PackedScene = load("res://UserInterface/upgrade_health.tscn")
	if health_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_health.tscn")
		get_tree().quit(1)
		return
	var health_icon: UpgradeIcon = health_scene.instantiate() as UpgradeIcon
	if health_icon == null:
		printerr("TEST FAILED: UpgradeHealth is not an instance of UpgradeIcon")
		get_tree().quit(1)
		return
	if (health_icon.get("health_bonus") as float) != 20.0:
		printerr("TEST FAILED: UpgradeHealth default health_bonus expected 20.0, got: ", health_icon.get("health_bonus"))
		get_tree().quit(1)
		return
	if health_icon.text_template != "%d -> [color='7fffd4']%d[/color] HP":
		printerr("TEST FAILED: UpgradeHealth text_template incorrect: ", health_icon.text_template)
		get_tree().quit(1)
		return

	# Test player health upgrade functionality
	var player_scene_hp: PackedScene = load("res://Player/player.tscn")
	var hp_player: Player = player_scene_hp.instantiate() as Player
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
		printerr("TEST FAILED: health_icon did not emit upgrade_taken with self via super.take_upgrade()")
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
	print("  25. UpgradeShop upgrade_container, upgrade_taken signal & exit_shop verified  ")
	print("  26. Window scaling & ui_toggle_fullscreen autoload verified       ")
	print("  27. Base UpgradeIcon scene, styling, and UpgradeShop placement ok ")
	print("====================================================================")
	
	get_tree().quit(0)


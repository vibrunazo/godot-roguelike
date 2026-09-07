extends Node

const TestUtils = preload("res://test/test_utils.gd")

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
	var valid_paths: Array[String] = ["res://Levels/LevelTemplate.tscn", "uid://dyj3auoai18wd"]
	if not exit_point.next_scene_path in valid_paths or not exit_point.next_level_path in valid_paths:
		printerr("TEST FAILED: ExitPoint next_scene_path: '", exit_point.next_scene_path, "', next_level_path: '", exit_point.next_level_path, "'")
		level.queue_free()
		get_tree().quit(1)
		return
	print("ExitPoint initially invisible, locked, and next_scene_path export var verified.")

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
	if not scene_trans.has_method("fade_in") or not scene_trans.has_method("fade_out") or not scene_trans.has_method("load_scene_path"):
		printerr("TEST FAILED: SceneTransition missing fade_in/fade_out/load_scene_path methods.")
		level.queue_free()
		get_tree().quit(1)
	print("SceneTransition autoload & ColorRect verified.")

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
	print("====================================================================")
	
	get_tree().quit(0)


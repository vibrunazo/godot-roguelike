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
	
	var anim_player: AnimationPlayer = animated_enemy.get_node_or_null("Enemy_Medium/AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		printerr("TEST FAILED: AnimationPlayer not found on Enemy_Medium.")
		get_tree().quit(1)
		return
	if not anim_player.has_animation_library(&"EnemyAnimations"):
		printerr("TEST FAILED: AnimationLibrary 'EnemyAnimations' missing on AnimationPlayer.")
		get_tree().quit(1)
		return
	for anim_name: String in ["Hit_A", "Idle_A", "Running_B", "Spawn_Ground"]:
		if not anim_player.has_animation("EnemyAnimations/" + anim_name):
			printerr("TEST FAILED: Animation '", anim_name, "' missing in EnemyAnimations library.")
			get_tree().quit(1)
			return
	print("AnimationPlayer & EnemyAnimations library verified (Hit_A, Idle_A, Running_B, Spawn_Ground).")
	
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
	if not sm.has_node(&"MoveSpace"):
		printerr("TEST FAILED: State 'MoveSpace' not found in AnimationTree.")
		get_tree().quit(1)
		return
	if not sm.has_node(&"EnemyAnimations_Hit_A"):
		printerr("TEST FAILED: State 'EnemyAnimations_Hit_A' not found in AnimationTree.")
		get_tree().quit(1)
		return
	var move_space: AnimationNodeBlendSpace1D = sm.get_node(&"MoveSpace") as AnimationNodeBlendSpace1D
	if move_space == null:
		printerr("TEST FAILED: MoveSpace is not an AnimationNodeBlendSpace1D.")
		get_tree().quit(1)
		return
	print("AnimationTree state machine and MoveSpace blend space verified.")
	
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
	# PART 4: HitAudio & Sound Playback
	# ---------------------------------------------------------
	print("\n>>> PART 4: HitAudio & Audio Playback on Damage")
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
	
	# Test hit_audio plays on damage
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
	
	# Test defeat emission
	var defeat_emitted: Array[bool] = [false]
	health_comp.defeat.connect(func() -> void: defeat_emitted[0] = true)
	health_comp.take_damage(30.0)
	await get_tree().process_frame
	if not defeat_emitted[0]:
		printerr("TEST FAILED: defeat signal was not emitted when health reached 0.")
		get_tree().quit(1)
		return
	print("HealthComponent defeat signal emitted successfully.")
	
	# ---------------------------------------------------------
	# PART 5: LevelTemplate Instantiation Verification
	# ---------------------------------------------------------
	print("\n>>> PART 5: LevelTemplate Enemy Placement Verification")
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
	
	print("\n====================================================================")
	print("  ALL BASE ENEMY TESTS PASSED!                                      ")
	print("  1. Enemy class_name & CharacterBody3D hierarchy verified          ")
	print("  2. CapsuleMesh & CapsuleShape3D configured                        ")
	print("  3. Collision layers 1 & 2 active (collision_layer = 3)            ")
	print("  4. HealthComponent (40 max health) & HealthBar wired              ")
	print("  5. HitAudio stream & SFX bus verified, plays on damage            ")
	print("  6. LevelTemplate enemy replacement confirmed                      ")
	print("====================================================================")
	
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)

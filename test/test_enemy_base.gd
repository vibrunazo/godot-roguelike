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
	# PART 2: Mesh & Collision Shape
	# ---------------------------------------------------------
	print("\n>>> PART 2: Mesh and Collision Shape Checks")
	var mesh_instance: MeshInstance3D = enemy.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		printerr("TEST FAILED: MeshInstance3D node not found on Enemy.")
		get_tree().quit(1)
		return
	if not (mesh_instance.mesh is CapsuleMesh):
		printerr("TEST FAILED: MeshInstance3D mesh is not a CapsuleMesh.")
		get_tree().quit(1)
		return
	print("MeshInstance3D with CapsuleMesh verified.")
	
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

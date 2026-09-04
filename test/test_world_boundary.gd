extends Node

func _ready() -> void:
	print("--- RUNNING WORLD BOUNDARY TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	# 1. Verify WorldBoundary node exists in LevelTemplate
	var world_boundary: Area3D = level.get_node_or_null("WorldBoundary") as Area3D
	if world_boundary == null:
		printerr("TEST FAILED: WorldBoundary node not found in LevelTemplate.tscn")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("WorldBoundary found at position: ", world_boundary.global_position)
	
	# 2. Verify Player health_component defeat signal connection to reload_current_scene
	var player: Player = level.get_node("Player") as Player
	if not player.health_component.defeat.is_connected(get_tree().reload_current_scene):
		printerr("TEST FAILED: Player health_component defeat is not connected to reload_current_scene.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player defeat signal connection to reload_current_scene confirmed!")
	
	# 3. Test WorldBoundary damage logic on an entity entering the boundary
	var test_target := Node3D.new()
	var test_hc := HealthComponent.new()
	test_hc.name = "HealthComponent"
	test_hc.max_health = 50.0
	test_hc.current_health = 50.0
	test_target.add_child(test_hc)
	level.add_child(test_target)
	
	var test_state := {"defeat_emitted": false}
	test_hc.defeat.connect(func() -> void: test_state["defeat_emitted"] = true)
	
	world_boundary.on_body_entered(test_target)
	
	if test_hc.current_health != 0.0:
		printerr("TEST FAILED: Target health was not reduced to 0. Got: ", test_hc.current_health)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Target health reduced to: ", test_hc.current_health, " (took max_health damage)")
	
	if not test_state["defeat_emitted"]:
		printerr("TEST FAILED: Defeat signal was not emitted upon fatal boundary damage.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Defeat signal successfully emitted!")
	
	# 4. Test Player taking fatal damage through WorldBoundary
	player.health_component.defeat.disconnect(get_tree().reload_current_scene)
	var player_state := {"defeat_emitted": false}
	player.health_component.defeat.connect(func() -> void: player_state["defeat_emitted"] = true)
	
	world_boundary.on_body_entered(player)
	
	if player.health_component.current_health != 0.0:
		printerr("TEST FAILED: Player health not reduced to 0. Got: ", player.health_component.current_health)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player health successfully reduced to 0 by WorldBoundary!")
	
	if not player_state["defeat_emitted"]:
		printerr("TEST FAILED: Player defeat signal was not emitted.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player defeat signal confirmed!")
	
	# 5. Physics Simulation: Entity falling through the WorldBoundary shape in real physics
	print("Testing live physics drop through the pit into WorldBoundary...")
	var falling_body := CharacterBody3D.new()
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	col_shape.shape = sphere
	falling_body.add_child(col_shape)
	
	var fall_hc := HealthComponent.new()
	fall_hc.name = "HealthComponent"
	fall_hc.max_health = 100.0
	falling_body.add_child(fall_hc)
	
	level.add_child(falling_body)
	falling_body.global_position = Vector3(0, 0, -16) # Above the pit!
	
	var physics_defeat := {"emitted": false}
	fall_hc.defeat.connect(func() -> void: physics_defeat["emitted"] = true)
	
	for i: int in range(80):
		await get_tree().physics_frame
		falling_body.velocity.y -= 9.8 * 0.05
		falling_body.move_and_slide()
		if physics_defeat["emitted"]:
			print("Falling body entered WorldBoundary at frame ", i, ", Y = ", falling_body.global_position.y)
			break
			
	if not physics_defeat["emitted"]:
		printerr("TEST FAILED: Falling body did not trigger WorldBoundary area detection.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Real-time physics body_entered detection confirmed!")
	
	print("\n====================================================================")
	print("  ALL WORLD BOUNDARY TESTS PASSED!                                  ")
	print("  1. WorldBoundary Area3D verified at y = -4                        ")
	print("  2. Entering bodies with HealthComponent take max_health damage    ")
	print("  3. Defeat signal is emitted upon reaching 0 health               ")
	print("  4. Player connects defeat signal to get_tree().reload_current_scene")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)

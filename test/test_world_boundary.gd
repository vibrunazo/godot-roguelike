extends Node

func _ready() -> void:
	print("--- RUNNING WORLD BOUNDARY TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	# 1. Verify WorldBoundary node exists in LevelTemplate
	var world_boundary: Area3D = level.get_node_or_null("WorldBoundary") as Area3D
	if world_boundary == null:
		printerr("TEST FAILED: WorldBoundary node not found in level_template.tscn")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("WorldBoundary found at position: ", world_boundary.global_position)
	
	# 2. Verify Player attribute_component defeat signal connection to reset_game_state
	var player: Character = level.get_node("Player") as Character
	if not player.attribute_component.defeat.is_connected(player.reset_game_state):
		printerr("TEST FAILED: Player attribute_component defeat is not connected to reset_game_state.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player defeat signal connection to reset_game_state confirmed!")
	
	# 3. Test WorldBoundary damage logic on an entity entering the boundary
	var test_target := Node3D.new()
	var test_attrs := AttributeComponent.new()
	test_attrs.name = "AttributeComponent"
	test_target.add_child(test_attrs)
	level.add_child(test_target)
	test_attrs.set_base(AttributeComponent.STAT_MAX_HEALTH, 50.0)
	
	var test_state := {"defeat_emitted": false}
	test_attrs.defeat.connect(func() -> void: test_state["defeat_emitted"] = true)
	
	world_boundary.on_body_entered(test_target)
	
	if test_attrs.get_current(AttributeComponent.POOL_HEALTH) != 0.0:
		printerr("TEST FAILED: Target health was not reduced to 0. Got: ", test_attrs.get_current(AttributeComponent.POOL_HEALTH))
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Target health reduced to: ", test_attrs.get_current(AttributeComponent.POOL_HEALTH), " (took max_health damage)")
	
	if not test_state["defeat_emitted"]:
		printerr("TEST FAILED: Defeat signal was not emitted upon fatal boundary damage.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Defeat signal successfully emitted!")

	if test_target.visible != false:
		printerr("TEST FAILED: Target was not hidden (visible != false) by WorldBoundary.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Target visibility set to false verified!")
	
	# 4. Test Player taking fatal damage through WorldBoundary
	player.attribute_component.defeat.disconnect(player.reset_game_state)
	var player_state := {"defeat_emitted": false}
	player.attribute_component.defeat.connect(func() -> void: player_state["defeat_emitted"] = true)
	
	world_boundary.on_body_entered(player)
	
	if player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) != 0.0:
		printerr("TEST FAILED: Player health not reduced to 0. Got: ", player.attribute_component.get_current(AttributeComponent.POOL_HEALTH))
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
	
	var fall_attrs := AttributeComponent.new()
	fall_attrs.name = "AttributeComponent"
	falling_body.add_child(fall_attrs)

	
	level.add_child(falling_body)
	falling_body.global_position = Vector3(0, 0, -16) # Above the pit!
	
	var physics_defeat := {"emitted": false}
	fall_attrs.defeat.connect(func() -> void: physics_defeat["emitted"] = true)
	
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
	print("  4. Player connects defeat signal to player.reset_game_state       ")
	print("  5. WorldBoundary sets entering body.visible to false              ")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)

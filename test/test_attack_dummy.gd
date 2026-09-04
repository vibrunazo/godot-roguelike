extends Node

func _ready() -> void:
	print("--- RUNNING ATTACK DUMMY TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: StaticBody3D = level.get_node("StaticBody3D") as StaticBody3D
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	print("Dummy initial health: ", health_comp.current_health)
	
	# Wait for player to land on floor in PlayerRun state
	var landed := false
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			landed = true
			break
			
	if not landed:
		printerr("TEST FAILED: Player did not settle on floor.")
		get_tree().quit(1)
		return
		
	# Position player in front of dummy and face it
	player.global_position = Vector3(0, player.global_position.y, 2.7)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.player_root.global_transform.looking_at(player.player_root.global_position + dir, Vector3.UP, true)
	player.player_root.global_transform = target
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Send click input
	var ev := InputEventAction.new()
	ev.action = "click"
	ev.pressed = true
	sm._unhandled_input(ev)
	
	print("State after click: ", sm.state.name)
	
	# Wait for animation and hitbox to hit dummy
	var hit := false
	for i: int in range(80):
		await get_tree().physics_frame
		if health_comp.current_health < 100.0:
			hit = true
			print("HIT CONFIRMED! Dummy health reduced to: ", health_comp.current_health, " on frame ", i)
			break
			
	print("Final Health: ", health_comp.current_health)
	if hit and health_comp.current_health == 92.0:
		print("================================")
		print("  ALL TESTS PASSED (100% OK)    ")
		print("================================")
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0)
	else:
		printerr("TEST FAILED: Health was not reduced to 92.0 as expected. Got: ", health_comp.current_health)
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(1)

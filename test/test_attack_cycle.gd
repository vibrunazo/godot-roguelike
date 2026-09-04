extends Node

func _ready() -> void:
	print("--- RUNNING ATTACK CYCLE & RECOVERY TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: StaticBody3D = level.get_node("StaticBody3D") as StaticBody3D
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	print("Dummy initial health: ", health_comp.current_health)
	
	# Wait for player to settle in PlayerRun on floor
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
			
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		get_tree().quit(1)
		return
		
	# Position player facing dummy
	player.global_position = Vector3(0, player.global_position.y, 2.7)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.player_root.global_transform.looking_at(player.player_root.global_position + dir, Vector3.UP, true)
	player.player_root.global_transform = target
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# === ATTACK 1 ===
	print("\n--- Triggering Attack 1 ---")
	var ev1 := InputEventAction.new()
	ev1.action = "click"
	ev1.pressed = true
	sm._unhandled_input(ev1)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not transition to PlayerAttack on first click. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (Attack 1)")
	
	# Wait for first hit (health 100 -> 95)
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= 95.0:
			break
			
	if health_comp.current_health != 95.0:
		printerr("TEST FAILED: First attack did not reduce health to 95.0. Health: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 1 hit confirmed! Dummy health: ", health_comp.current_health)
	
	# Wait for animation to finish and return to PlayerRun
	var returned_to_run := false
	for i: int in range(100):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			returned_to_run = true
			print("Attack 1 completed! Automatically returned to PlayerRun at frame ", i)
			break
			
	if not returned_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after Attack 1 finished. State: ", sm.state.name)
		get_tree().quit(1)
		return
		
	# === ATTACK 2 ===
	print("\n--- Triggering Attack 2 (Testing repeat attack & exception reset) ---")
	var ev2 := InputEventAction.new()
	ev2.action = "click"
	ev2.pressed = true
	sm._unhandled_input(ev2)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not transition to PlayerAttack on second click. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (Attack 2)")
	
	# Wait for second hit (health 95 -> 90)
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= 90.0:
			break
			
	if health_comp.current_health != 90.0:
		printerr("TEST FAILED: Second attack did not reduce health to 90.0. Health: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 2 hit confirmed! Dummy health: ", health_comp.current_health)
	
	# Wait for animation to finish and return to PlayerRun again
	returned_to_run = false
	for i: int in range(100):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			returned_to_run = true
			print("Attack 2 completed! Automatically returned to PlayerRun at frame ", i)
			break
			
	if not returned_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after Attack 2 finished. State: ", sm.state.name)
		get_tree().quit(1)
		return
		
	print("\n========================================================")
	print("  ATTACK CYCLE TEST PASSED: State exits and re-enters! ")
	print("  Final Dummy Health: ", health_comp.current_health, " (Started at 100.0)      ")
	print("========================================================")
	get_tree().quit(0)

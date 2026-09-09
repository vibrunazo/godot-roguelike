extends Node

const TestUtils = preload("res://test/test_utils.gd")

func _ready() -> void:
	print("--- RUNNING ATTACK CYCLE & RECOVERY TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Character = level.get_node("Player") as Character
	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	# Wait for initial spawn/navigation repositioning timer (1.0s) to settle, then for player to land on floor
	await get_tree().create_timer(1.1).timeout
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
			
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		get_tree().quit(1)
		return
		
	# Position player facing dummy
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	player.mesh_mount.global_transform = target
	
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
	
	# Wait for first hit
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 8.0:
			break
			
	if health_comp.current_health != initial_health - 8.0:
		printerr("TEST FAILED: First attack did not reduce health to expected value. Health: ", health_comp.current_health)
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
	# Re-align player facing dummy in case dummy was repositioned (e.g. by navigation spawn)
	player.global_position = Vector3(dummy.global_position.x, dummy.global_position.y, dummy.global_position.z - 1.3)
	player.mesh_mount.global_transform = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	for i: int in range(60):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break

	var ev2 := InputEventAction.new()
	ev2.action = "click"
	ev2.pressed = true
	sm._unhandled_input(ev2)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not transition to PlayerAttack on second click. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (Attack 2)")
	
	# Wait for second hit
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 16.0:
			break
			
	if health_comp.current_health != initial_health - 16.0:
		printerr("TEST FAILED: Second attack did not reduce health to expected value. Health: ", health_comp.current_health)
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
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
